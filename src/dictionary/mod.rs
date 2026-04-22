use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::Write;
use std::path::PathBuf;

use base64::Engine;
use sha2::{Digest, Sha256};

use crate::cli::DictionaryArgs;
use crate::error::{Error, Result};
use crate::io::{canonicalized_inputs, ensure_parent, relative_path};

#[derive(Debug)]
struct InputFile {
  rel_path: String,
  data: Vec<u8>,
  slice_ids: Vec<Option<usize>>,
  selected_ranges: Vec<(usize, usize)>,
}

#[derive(Clone, Copy, Debug)]
struct Candidate {
  file_index: usize,
  score: usize,
  position: usize,
  generation: usize,
}

#[derive(Debug)]
struct MaxHeap {
  data: Vec<Candidate>,
}

impl MaxHeap {
  fn new() -> Self {
    Self { data: Vec::new() }
  }

  fn empty(&self) -> bool {
    self.data.is_empty()
  }

  fn peek(&self) -> Option<Candidate> {
    self.data.first().copied()
  }

  fn higher_priority(left: Candidate, right: Candidate) -> bool {
    if left.score != right.score {
      left.score > right.score
    } else if left.file_index != right.file_index {
      left.file_index < right.file_index
    } else {
      left.position < right.position
    }
  }

  fn push(&mut self, item: Candidate) {
    self.data.push(item);
    let mut index = self.data.len() - 1;
    while index > 0 {
      let parent = (index - 1) / 2;
      if !Self::higher_priority(self.data[index], self.data[parent]) {
        break;
      }
      self.data.swap(index, parent);
      index = parent;
    }
  }

  fn pop(&mut self) -> Option<Candidate> {
    if self.data.is_empty() {
      return None;
    }
    let top = self.data.swap_remove(0);
    let size = self.data.len();
    let mut index = 0;
    while index < size {
      let left = index * 2 + 1;
      let right = left + 1;
      let mut best = index;
      if left < size && Self::higher_priority(self.data[left], self.data[best]) {
        best = left;
      }
      if right < size && Self::higher_priority(self.data[right], self.data[best]) {
        best = right;
      }
      if best == index {
        break;
      }
      self.data.swap(index, best);
      index = best;
    }
    Some(top)
  }
}

fn add_range(ranges: &mut Vec<(usize, usize)>, start_pos: usize, end_pos: usize) {
  if start_pos >= end_pos {
    return;
  }

  let mut merged_start = start_pos;
  let mut merged_end = end_pos;
  let mut index = 0;

  while index < ranges.len() && ranges[index].1 < merged_start {
    index += 1;
  }

  while index < ranges.len() && ranges[index].0 <= merged_end {
    merged_start = merged_start.min(ranges[index].0);
    merged_end = merged_end.max(ranges[index].1);
    ranges.remove(index);
  }

  ranges.insert(index, (merged_start, merged_end));
}

fn subtract_ranges(start_pos: usize, end_pos: usize, ranges: &[(usize, usize)]) -> Vec<(usize, usize)> {
  let mut cursor = start_pos;
  let mut residuals = Vec::new();
  for (range_start, range_end) in ranges {
    if *range_end <= cursor {
      continue;
    }
    if *range_start >= end_pos {
      break;
    }
    if *range_start > cursor {
      residuals.push((cursor, (*range_start).min(end_pos)));
    }
    cursor = cursor.max(*range_end);
    if cursor >= end_pos {
      break;
    }
  }
  if cursor < end_pos {
    residuals.push((cursor, end_pos));
  }
  residuals
}

fn qualifying_slice(slice_id: Option<usize>, active_scores: &[usize]) -> bool {
  slice_id.is_some_and(|id| active_scores[id] > 0)
}

fn trim_block(slice_ids: &[Option<usize>], start_pos: usize, window_span: usize, slice_length: usize, active_scores: &[usize]) -> Option<(usize, usize)> {
  let mut left = start_pos;
  let mut right = start_pos + window_span - 1;
  while left <= right && !qualifying_slice(slice_ids[left], active_scores) {
    left += 1;
  }
  if left > right {
    return None;
  }
  while right >= left && !qualifying_slice(slice_ids[right], active_scores) {
    right -= 1;
  }
  Some((left, right + slice_length))
}

fn block_residuals(file: &InputFile, start_pos: usize, window_span: usize, slice_length: usize, active_scores: &[usize]) -> Vec<(usize, usize)> {
  let Some((trimmed_start, trimmed_end)) = trim_block(&file.slice_ids, start_pos, window_span, slice_length, active_scores) else {
    return Vec::new();
  };
  subtract_ranges(trimmed_start, trimmed_end, &file.selected_ranges)
}

fn cover_block(slice_ids: &[Option<usize>], start_pos: usize, window_span: usize, active_scores: &mut [usize]) {
  let block_end = start_pos + window_span - 1;
  let mut seen = HashSet::<usize>::new();
  for &slice_id in slice_ids.iter().take(block_end + 1).skip(start_pos) {
    if let Some(slice_id) = slice_id
      && seen.insert(slice_id)
    {
      active_scores[slice_id] = 0;
    }
  }
}

fn refresh_file_candidate(file_index: usize, file: &InputFile, active_scores: &[usize], window_span: usize, generation: usize) -> Candidate {
  if file.slice_ids.len() < window_span {
    return Candidate { file_index, score: 0, position: 0, generation };
  }

  let mut counts = HashMap::<usize, usize>::new();
  let mut current_score = 0usize;
  let mut best_score = 0usize;
  let mut best_position = 0usize;
  let mut left = 0usize;

  for right in 0..file.slice_ids.len() {
    if let Some(slice_id) = file.slice_ids[right] {
      let count = counts.entry(slice_id).or_insert(0);
      if *count == 0 {
        current_score += active_scores[slice_id];
      }
      *count += 1;
    }

    while right - left + 1 > window_span {
      if let Some(drop_id) = file.slice_ids[left]
        && let Some(count) = counts.get_mut(&drop_id)
      {
        *count -= 1;
        if *count == 0 {
          counts.remove(&drop_id);
          current_score -= active_scores[drop_id];
        }
      }
      left += 1;
    }

    if right - left + 1 == window_span && current_score > best_score {
      best_score = current_score;
      best_position = left;
    }
  }

  Candidate { file_index, score: best_score, position: best_position, generation }
}

pub fn run(args: DictionaryArgs) -> Result<()> {
  if args.output.is_some() && args.output_dir.is_some() {
    return Err(Error::message("--output and --output-dir are mutually exclusive"));
  }
  if args.slice_length == 0 || args.block_length == 0 || args.size == 0 || args.min_frequency == 0 {
    return Err(Error::message("options must be positive"));
  }
  if args.block_length < args.slice_length {
    return Err(Error::message("block length must be >= slice length"));
  }

  let cwd = std::env::current_dir()?;
  let paths = canonicalized_inputs(&args.inputs, &cwd)?;
  if paths.is_empty() {
    return Err(Error::message("no input files"));
  }

  let mut files = Vec::with_capacity(paths.len());
  for path in paths {
    let data = fs::read(&path)?;
    let rel = relative_path(&path, &cwd);
    files.push(InputFile {
      rel_path: rel,
      data,
      slice_ids: Vec::new(),
      selected_ranges: Vec::new(),
    });
  }

  if args.verbose {
    eprintln!(
      "reading {} files ({} bytes)",
      files.len(),
      files.iter().map(|file| file.data.len()).sum::<usize>()
    );
  }

  let slice_length = args.slice_length;
  let block_length = args.block_length;
  let window_span = block_length - slice_length + 1;

  let mut document_frequency = HashMap::<Vec<u8>, usize>::new();
  for (index, file) in files.iter().enumerate() {
    if file.data.len() < slice_length {
      continue;
    }
    let mut seen = HashSet::<Vec<u8>>::new();
    let limit = file.data.len() - slice_length;
    for pos in 0..=limit {
      seen.insert(file.data[pos..pos + slice_length].to_vec());
    }
    for key in seen.into_iter() {
      *document_frequency.entry(key).or_insert(0) += 1;
    }
    if args.verbose {
      eprintln!("  counted {}/{}: {}", index + 1, files.len(), file.rel_path);
    }
  }

  let mut qualifying = document_frequency
    .into_iter()
    .filter(|(_, score)| *score >= args.min_frequency)
    .collect::<Vec<_>>();
  qualifying.sort_by(|left, right| left.0.cmp(&right.0));

  if qualifying.is_empty() {
    return Err(Error::message("no slices found matching criteria"));
  }

  let mut slice_lookup = HashMap::<Vec<u8>, usize>::new();
  let mut active_scores = Vec::with_capacity(qualifying.len());
  for (index, (slice, score)) in qualifying.into_iter().enumerate() {
    slice_lookup.insert(slice, index);
    active_scores.push(score);
  }

  if args.verbose {
    eprintln!("qualified {} slices (freq >= {})", active_scores.len(), args.min_frequency);
  }

  for file in &mut files {
    if file.data.len() < slice_length {
      continue;
    }
    let slice_count = file.data.len() - slice_length + 1;
    let mut slice_ids = Vec::with_capacity(slice_count);
    for pos in 0..slice_count {
      let slice = &file.data[pos..pos + slice_length];
      slice_ids.push(slice_lookup.get(slice).copied());
    }
    file.slice_ids = slice_ids;
  }
  drop(slice_lookup);

  let mut heap = MaxHeap::new();
  let mut generation = 0usize;
  for (index, file) in files.iter().enumerate() {
    heap.push(refresh_file_candidate(index, file, &active_scores, window_span, generation));
  }

  let mut selected_bytes = 0usize;
  let mut selected_blocks = 0usize;
  while selected_bytes < args.size && !heap.empty() {
    let Some(candidate) = heap.pop() else { break };
    if candidate.score == 0 {
      break;
    }
    if candidate.generation != generation {
      heap.push(refresh_file_candidate(candidate.file_index, &files[candidate.file_index], &active_scores, window_span, generation));
      continue;
    }
    if let Some(top) = heap.peek()
      && MaxHeap::higher_priority(top, candidate)
    {
      heap.push(candidate);
      continue;
    }
    let file = &mut files[candidate.file_index];
    let mut remaining = args.size - selected_bytes;
    for (range_start, mut range_end) in block_residuals(file, candidate.position, window_span, slice_length, &active_scores) {
      if remaining == 0 {
        break;
      }
      if range_end - range_start > remaining {
        range_end = range_start + remaining;
      }
      add_range(&mut file.selected_ranges, range_start, range_end);
      let length = range_end - range_start;
      selected_bytes += length;
      remaining -= length;
    }
    cover_block(&file.slice_ids, candidate.position, window_span, &mut active_scores);
    generation += 1;
    selected_blocks += 1;
    heap.push(refresh_file_candidate(candidate.file_index, file, &active_scores, window_span, generation));

    if args.verbose {
      let mut stderr = std::io::stderr().lock();
      let _ = write!(stderr, "\r  selected {selected_blocks} blocks ({selected_bytes}/{} bytes)", args.size);
      let _ = stderr.flush();
    }
  }

  let mut dictionary = Vec::with_capacity(args.size);
  for file in &files {
    for (range_start, range_end) in &file.selected_ranges {
      if dictionary.len() >= args.size {
        break;
      }
      let remaining = args.size - dictionary.len();
      let length = (*range_end - *range_start).min(remaining);
      dictionary.extend_from_slice(&file.data[*range_start..*range_start + length]);
    }
  }

  let sha256_digest = Sha256::digest(&dictionary);
  let sha256_hex = format!("{sha256_digest:x}");

  let output_path = if let Some(output_dir) = args.output_dir {
    let path = output_dir.join(format!("{sha256_hex}.dict"));
    ensure_parent(&path)?;
    path
  } else {
    let path = args.output.unwrap_or_else(|| PathBuf::from("dictionary.dict"));
    ensure_parent(&path)?;
    path
  };

  let bytes_written = dictionary.len();
  fs::write(&output_path, dictionary)?;

  if args.verbose {
    let sha256_base64 = base64::engine::general_purpose::STANDARD.encode(sha256_digest);
    eprintln!();
    eprintln!("wrote {} ({bytes_written} bytes)", output_path.display());
    eprintln!("sha256: :{sha256_base64}:");
  }

  println!("{}", output_path.display());
  Ok(())
}

pub fn dictionary_hash(bytes: &[u8]) -> [u8; 32] {
  Sha256::digest(bytes).into()
}
