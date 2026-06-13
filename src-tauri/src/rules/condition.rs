use std::path::Path;

use anyhow::Result;

use super::model::{Condition, ConditionKind, Operator};

/// Returns true if the file at `path` satisfies the condition.
pub fn evaluate(condition: &Condition, path: &Path) -> Result<bool> {
    let meta = std::fs::metadata(path)?;

    match &condition.kind {
        ConditionKind::Name => {
            let name = path.file_stem().and_then(|s| s.to_str()).unwrap_or("");
            Ok(match_string(&condition.operator, name, &condition.value))
        }

        ConditionKind::Extension => {
            let ext = path
                .extension()
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .to_lowercase();
            let value = condition.value.trim_start_matches('.').to_lowercase();
            Ok(match_string(&condition.operator, &ext, &value))
        }

        ConditionKind::Kind => {
            let detected = detect_kind(path, &meta);
            Ok(match condition.operator {
                Operator::Is => detected == condition.value,
                Operator::IsNot => detected != condition.value,
                _ => false,
            })
        }

        ConditionKind::SizeBytes => {
            let size = meta.len();
            let threshold: u64 = condition.value.parse().unwrap_or(0);
            Ok(match condition.operator {
                Operator::Is => size == threshold,
                Operator::IsNot => size != threshold,
                Operator::GreaterThan => size > threshold,
                Operator::LessThan => size < threshold,
                _ => false,
            })
        }

        ConditionKind::ColorLabel => {
            let target = condition.value.to_lowercase();
            let has = super::action::read_file_tags(path).iter().any(|tag| {
                // A label may be stored as "Red\n6" — compare the name part only.
                let name = tag.split('\n').next().unwrap_or(tag).trim().to_lowercase();
                name == target
            });
            Ok(match condition.operator {
                Operator::Is => has,
                Operator::IsNot => !has,
                _ => false,
            })
        }

        ConditionKind::Contents => {
            let text = std::fs::read_to_string(path).unwrap_or_default();
            Ok(match_string(&condition.operator, &text, &condition.value))
        }
    }
}

/// Classifies a file into a Hazel-style kind string based on its extension.
fn detect_kind(path: &Path, meta: &std::fs::Metadata) -> &'static str {
    if meta.is_dir() {
        return if path.extension().and_then(|e| e.to_str()) == Some("app") {
            "application"
        } else {
            "folder"
        };
    }

    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase());

    match ext.as_deref() {
        Some(
            "jpg" | "jpeg" | "png" | "gif" | "bmp" | "tiff" | "tif" | "webp" | "svg" | "heic"
            | "heif" | "raw" | "cr2" | "cr3" | "nef" | "arw" | "dng",
        ) => "image",

        Some("mp4" | "mov" | "avi" | "mkv" | "m4v" | "wmv" | "flv" | "webm" | "mpg" | "mpeg") => {
            "movie"
        }

        Some("mp3" | "aac" | "flac" | "wav" | "aiff" | "aif" | "m4a" | "ogg" | "wma" | "opus") => {
            "music"
        }

        Some("pdf") => "pdf",

        Some("txt" | "md" | "markdown" | "rtf" | "rst" | "log") => "text",

        Some("ppt" | "pptx" | "key" | "odp") => "presentation",

        Some(
            "zip" | "tar" | "gz" | "bz2" | "7z" | "rar" | "xz" | "zst" | "tgz" | "tbz" | "cab",
        ) => "archive",

        Some("dmg" | "iso" | "img" | "sparseimage" | "sparsebundle") => "disk_image",

        Some(
            "doc" | "docx" | "odt" | "pages" | "xls" | "xlsx" | "ods" | "numbers" | "csv"
            | "epub",
        ) => "document",

        _ => "document",
    }
}

fn match_string(operator: &Operator, haystack: &str, needle: &str) -> bool {
    match operator {
        Operator::Is => haystack == needle,
        Operator::IsNot => haystack != needle,
        Operator::Contains => haystack.contains(needle),
        Operator::DoesNotContain => !haystack.contains(needle),
        Operator::StartsWith => haystack.starts_with(needle),
        Operator::EndsWith => haystack.ends_with(needle),
        Operator::MatchesRegex => regex::Regex::new(needle)
            .map(|re| re.is_match(haystack))
            .unwrap_or(false),
        _ => false,
    }
}
