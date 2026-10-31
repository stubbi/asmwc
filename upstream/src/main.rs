use std::fmt::Write as _;
use std::fs::{File, Metadata};
use std::io::{self, BufReader, Read, Write};
use std::path::{Path, PathBuf};

use clap::Parser;
use rayon::prelude::*;
use walkdir::WalkDir;

#[derive(Parser)]
#[clap(author="https://github.com/LuminousToaster", version=env!("CARGO_PKG_VERSION"), about="A rewrite of the GNU coreutils 'wc' tool.", long_about = None)]
struct Args {
	#[clap(value_parser, help="The file or folder to read", required=true)]
	file: Vec<String>,
	#[clap(short='c', long, help="Print the byte counts")]
	bytes: bool,
	#[clap(short='m', long, help="Print the character counts")]
	chars: bool,
	#[clap(short='l', long, help="Print newline counts")]
	lines: bool,
	#[clap(short='w', long, help="Print word counts")]
	words: bool,
	#[clap(short='L', long, help="Print maximum display width")]
	max_line_length: bool,
	#[clap(short='r', long, help="Recursively search through folders and files")]
	recursive: bool,
	#[clap(short='v', help="Print verbose output")]
	verbose: bool,
}

// Struct to hold count data
#[derive(Default, Clone)]
struct Counts {
	bytes: usize,
	chars: usize,
	words: usize,
	lines: usize,
	max_line_length: usize,
}

impl Counts {
	fn add(&mut self, other: &Counts) {
		self.bytes += other.bytes;
		self.chars += other.chars;
		self.words += other.words;
		self.lines += other.lines;
		self.max_line_length = self.max_line_length.max(other.max_line_length);
	}
}

static IS_WHITESPACE: [bool; 256] = {
	let mut table = [false; 256];
	table[b' ' as usize] = true;
	table[b'\t' as usize] = true;
	table[b'\n' as usize] = true;
	table[b'\r' as usize] = true;
	table
};

#[inline(always)]
fn main() -> io::Result<()> {
	rayon::ThreadPoolBuilder::new().num_threads(num_cpus::get()).build_global().unwrap();
	let mut app = Args::parse();
	// Set default flags if none are specified
	if !app.bytes && !app.lines && !app.words && !app.chars && !app.max_line_length {
		app.bytes = true;
		app.lines = true;
		app.words = true;
	}
	let mut total_counts = Counts::default();
	let mut file_count = 0;
	let mut result = String::with_capacity(128);
	let stdout = io::stdout();
	let mut stdout = stdout.lock();

	// Collect paths and metadata
	let paths: Vec<(PathBuf, Option<Metadata>)> = app.file.iter().flat_map(|file_path| {
		WalkDir::new(file_path)	.sort_by_file_name().into_iter().filter_map(Result::ok).take(if app.recursive { usize::MAX } else { 1 }).map(|entry| {
			let path = entry.into_path();
			let metadata = std::fs::metadata(&path).ok();
			(path, metadata)})
	}).collect();

	// Process files in parallel with small-file batching
	let counts: Vec<(Counts, String)> = paths.par_iter().filter_map(|(path, metadata)| {
		// Batch small files (<512KB) sequentially
		if let Some(meta) = metadata {
			if meta.len() < 512 * 1024 {
				let mut counts = Counts::default();
				let result = process_file(path, Some(meta), &app).ok()?;
				counts.add(&result);
				let mut output = String::with_capacity(128);
				append_counts(&mut output, &counts, &app);
				return Some((counts, format!("{} {}", output.trim(), path.display())));
			}
		}
		if app.verbose {
			writeln!(io::stderr(), "Processing: {}", path.display()).ok()?;
		}
		let counts = process_file(path, metadata.as_ref(), &app).ok()?;
		let mut result = String::with_capacity(128);
		append_counts(&mut result, &counts, &app);
		Some((counts, format!("{} {}", result.trim(), path.display())))
	}).collect();
	// Aggregate results
	for (counts, output) in counts {
		file_count += 1;
		total_counts.add(&counts);
		writeln!(stdout, "{}", output)?;
	}
	// Print totals if multiple files were processed
	if file_count > 1 {
		result.clear();
		append_counts(&mut result, &total_counts, &app);
		writeln!(stdout, "\n{} total", result.trim())?;
	}
	Ok(())
}

// Process a single file and return its counts
#[inline(always)]
fn process_file(path: &Path, metadata: Option<&Metadata>, app: &Args) -> io::Result<Counts> {
	let file = File::open(path)?;
	let mut counts = Counts::default();
	// If only bytes are needed, use metadata
	if app.bytes && !app.lines && !app.words && !app.chars && !app.max_line_length {
		if let Some(meta) = metadata {
			counts.bytes = meta.len() as usize;
			return Ok(counts);
		}
	}
	// Use buffered reading with 1MB buffer on heap
	let mut reader = BufReader::with_capacity(1024 * 1024, file);
	let mut buffer = vec![0u8; 1024 * 1024];
	let mut in_word = false;
	let mut current_line_length = 0;

	loop {
		let bytes_read = reader.read(&mut buffer)?;
		if bytes_read == 0 {
			break;
		}
		// Process buffer with 8-byte unrolling
		let mut i = 0;
		unsafe {
			let ptr = buffer.as_ptr();
			while i + 7 < bytes_read {
				let b0 = *ptr.add(i);
				let b1 = *ptr.add(i + 1);
				let b2 = *ptr.add(i + 2);
				let b3 = *ptr.add(i + 3);
				let b4 = *ptr.add(i + 4);
				let b5 = *ptr.add(i + 5);
				let b6 = *ptr.add(i + 6);
				let b7 = *ptr.add(i + 7);
				if app.bytes {
					counts.bytes += 8;
				}
				if app.chars {
					if b0 != 0 { counts.chars += 1; }
					if b1 != 0 { counts.chars += 1; }
					if b2 != 0 { counts.chars += 1; }
					if b3 != 0 { counts.chars += 1; }
					if b4 != 0 { counts.chars += 1; }
					if b5 != 0 { counts.chars += 1; }
					if b6 != 0 { counts.chars += 1; }
					if b7 != 0 { counts.chars += 1; }
				}
				if app.lines {
					if b0 == b'\n' { counts.lines += 1; }
					if b1 == b'\n' { counts.lines += 1; }
					if b2 == b'\n' { counts.lines += 1; }
					if b3 == b'\n' { counts.lines += 1; }
					if b4 == b'\n' { counts.lines += 1; }
					if b5 == b'\n' { counts.lines += 1; }
					if b6 == b'\n' { counts.lines += 1; }
					if b7 == b'\n' { counts.lines += 1; }
				}
				if app.max_line_length {
					if b0 == b'\n' {
						counts.max_line_length = counts.max_line_length.max(current_line_length);
						current_line_length = 0;
					} else {
						current_line_length += 1;
					}
					if b1 == b'\n' {
						counts.max_line_length = counts.max_line_length.max(current_line_length);
						current_line_length = 0;
					} else {
						current_line_length += 1;
					}
					if b2 == b'\n' {
						counts.max_line_length = counts.max_line_length.max(current_line_length);
						current_line_length = 0;
					} else {
						current_line_length += 1;
					}
					if b3 == b'\n' {
						counts.max_line_length = counts.max_line_length.max(current_line_length);
						current_line_length = 0;
					} else {
						current_line_length += 1;
					}
					if b4 == b'\n' {
						counts.max_line_length = counts.max_line_length.max(current_line_length);
						current_line_length = 0;
					} else {
						current_line_length += 1;
					}
					if b5 == b'\n' {
						counts.max_line_length = counts.max_line_length.max(current_line_length);
						current_line_length = 0;
					} else {
						current_line_length += 1;
					}
					if b6 == b'\n' {
						counts.max_line_length = counts.max_line_length.max(current_line_length);
						current_line_length = 0;
					} else {
						current_line_length += 1;
					}
					if b7 == b'\n' {
						counts.max_line_length = counts.max_line_length.max(current_line_length);
						current_line_length = 0;
					} else {
						current_line_length += 1;
					}
				}
				if app.words {
					let ws0 = IS_WHITESPACE[b0 as usize];
					let ws1 = IS_WHITESPACE[b1 as usize];
					let ws2 = IS_WHITESPACE[b2 as usize];
					let ws3 = IS_WHITESPACE[b3 as usize];
					let ws4 = IS_WHITESPACE[b4 as usize];
					let ws5 = IS_WHITESPACE[b5 as usize];
					let ws6 = IS_WHITESPACE[b6 as usize];
					let ws7 = IS_WHITESPACE[b7 as usize];
					if !in_word && !ws0 {
						in_word = true;
					} else if in_word && ws0 {
						in_word = false;
						counts.words += 1;
					}
					if !in_word && !ws1 {
						in_word = true;
					} else if in_word && ws1 {
						in_word = false;
						counts.words += 1;
					}
					if !in_word && !ws2 {
						in_word = true;
					} else if in_word && ws2 {
						in_word = false;
						counts.words += 1;
					}
					if !in_word && !ws3 {
						in_word = true;
					} else if in_word && ws3 {
						in_word = false;
						counts.words += 1;
					}
					if !in_word && !ws4 {
						in_word = true;
					} else if in_word && ws4 {
						in_word = false;
						counts.words += 1;
					}
					if !in_word && !ws5 {
						in_word = true;
					} else if in_word && ws5 {
						in_word = false;
						counts.words += 1;
					}
					if !in_word && !ws6 {
						in_word = true;
					} else if in_word && ws6 {
						in_word = false;
						counts.words += 1;
					}
					if !in_word && !ws7 {
						in_word = true;
					} else if in_word && ws7 {
						in_word = false;
						counts.words += 1;
					}
				}
				i += 8;
			}

			// Process final bytes
			while i < bytes_read {
				let byte = *ptr.add(i);
				if app.bytes {
					counts.bytes += 1;
				}
				if app.chars && byte != 0 {
					counts.chars += 1;
				}
				if app.lines && byte == b'\n' {
					counts.lines += 1;
				}
				if app.max_line_length {
					if byte == b'\n' {
						counts.max_line_length = counts.max_line_length.max(current_line_length);
						current_line_length = 0;
					} else {
						current_line_length += 1;
					}
				}
				if app.words {
					let is_whitespace = IS_WHITESPACE[byte as usize];
					if !in_word && !is_whitespace {
						in_word = true;
					} else if in_word && is_whitespace {
						in_word = false;
						counts.words += 1;
					}
				}
				i += 1;
			}
		}
	}
	// Handle last word and line
	if app.words && in_word {
		counts.words += 1;
	}
	if app.max_line_length && current_line_length > 0 {
		counts.max_line_length = counts.max_line_length.max(current_line_length);
	}

	// Fallback to metadata for bytes if needed
	if app.bytes && counts.bytes == 0 {
		if let Some(meta) = metadata {
			counts.bytes = meta.len() as usize;
		}
	}
	Ok(counts)
}

// Append counts to the result string based on app flags
#[inline(always)]
fn append_counts(result: &mut String, counts: &Counts, app: &Args) {
	if app.lines && counts.lines > 0 {
		let _ = write!(result, " lines: {}", counts.lines);
	}
	if app.words && counts.words > 0 {
		let _ = write!(result, " words: {}", counts.words);
	}
	if app.chars && counts.chars > 0 {
		let _ = write!(result, " chars: {}", counts.chars);
	}
	if app.bytes && counts.bytes > 0 {
		let _ = write!(result, " bytes: {}", counts.bytes);
	}
	if app.max_line_length && counts.max_line_length > 0 {
		let _ = write!(result, " max line length: {}", counts.max_line_length);
	}
}
