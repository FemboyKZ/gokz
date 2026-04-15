#!/usr/bin/env python3
"""
Translation file linter for GOKZ phrase files.
Checks for format issues and missing/duplicate language entries.

Usage:
    python check-translations.py [base_directory]

If no directory is specified, defaults to current directory.
The script will look for:
  - addons/sourcemod/translations/ folder for phrase files

Ignoring sections:
    Use // lint-ignore-start and // lint-ignore-end comments to ignore sections.
    Use // lint-ignore-next to ignore the next line.
    Use // lint-ignore at the end of a line to ignore that specific line.

    Example:
        // lint-ignore-start
        "Problematic Phrase"
        {
            "en"    "This won't be checked"
        }
        // lint-ignore-end

        // lint-ignore-next
        "en"    "This line is also ignored"

        "en"    "Ignore this specific line"  // lint-ignore
"""

import json
import re
import sys
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional
from collections import defaultdict
from io import StringIO


@dataclass
class Issue:
    file: str
    line: int
    issue_type: str
    category: str
    message: str
    context: Optional[str] = None

    def __str__(self) -> str:
        prefix = "ERROR" if self.issue_type == "error" else "WARNING"
        msg = f"{self.file}:{self.line}: [{prefix}] {self.category}: {self.message}"
        if self.context:
            msg += f"\n    Context: {self.context}"
        return msg


@dataclass
class PhraseBlock:
    name: str
    start_line: int
    end_line: int
    languages: dict = field(default_factory=dict)
    format_spec: Optional[str] = None
    placeholders: set = field(default_factory=set)
    ignored: bool = False



class IgnoreTracker:

    IGNORE_START = "lint-ignore-start"
    IGNORE_END = "lint-ignore-end"
    IGNORE_NEXT = "lint-ignore-next"
    IGNORE_LINE = "lint-ignore"

    def __init__(self, lines: list[str]):
        self.ignored_lines: set[int] = set()
        self._parse_ignore_comments(lines)

    def _parse_ignore_comments(self, lines: list[str]) -> None:
        in_ignored_block = False
        ignore_next = False

        for line_num, line in enumerate(lines, 1):
            stripped = line.strip()

            if self.IGNORE_START in stripped:
                in_ignored_block = True
                self.ignored_lines.add(line_num)
                continue

            if self.IGNORE_END in stripped:
                in_ignored_block = False
                self.ignored_lines.add(line_num)
                continue

            if self.IGNORE_NEXT in stripped and self.IGNORE_START not in stripped:
                ignore_next = True
                self.ignored_lines.add(line_num)
                continue

            if in_ignored_block:
                self.ignored_lines.add(line_num)
                continue

            if ignore_next:
                self.ignored_lines.add(line_num)
                ignore_next = False
                continue

            if self.IGNORE_LINE in stripped:
                comment_part = stripped.split("//")[-1] if "//" in stripped else ""
                if self.IGNORE_LINE in comment_part:
                    if (self.IGNORE_START not in comment_part and
                        self.IGNORE_END not in comment_part and
                        self.IGNORE_NEXT not in comment_part):
                        self.ignored_lines.add(line_num)

    def is_ignored(self, line_num: int) -> bool:
        return line_num in self.ignored_lines

    def is_range_ignored(self, start_line: int, end_line: int) -> bool:
        return all(self.is_ignored(ln) for ln in range(start_line, end_line + 1))


class TranslationLinter:

    # fallback if config.txt is missing
    DEFAULT_LANGUAGE_MAP = {
        "arabic": "ar",
        "brazilian": "pt",
        "bulgarian": "bg",
        "czech": "cze",
        "danish": "da",
        "dutch": "nl",
        "english": "en",
        "finnish": "fi",
        "french": "fr",
        "german": "de",
        "greek": "el",
        "hebrew": "he",
        "hungarian": "hu",
        "italian": "it",
        "japanese": "jp",
        "koreana": "ko",
        "korean": "ko",
        "latvian": "lv",
        "lithuanian": "lt",
        "norwegian": "no",
        "polish": "pl",
        "portuguese": "pt_p",
        "romanian": "ro",
        "russian": "ru",
        "schinese": "chi",
        "slovak": "sk",
        "spanish": "es",
        "swedish": "sv",
        "tchinese": "zho",
        "thai": "th",
        "turkish": "tr",
        "ukrainian": "ua",
        "vietnamese": "vi",
    }

    KNOWN_COLOR_TAGS = {
        "default", "red", "lightred", "darkred", "bluegrey", "blue",
        "darkblue", "purple", "orchid", "yellow", "gold", "lightgreen",
        "green", "lime", "grey", "grey2"
    }

    def __init__(self, base_dir: str = "."):
        self.base_dir = Path(base_dir).resolve()
        self.translations_dir = self.base_dir / "addons" / "sourcemod" / "translations"

        self.issues: list[Issue] = []
        self.all_phrase_blocks: dict[str, list[PhraseBlock]] = {}
        self.ignore_trackers: dict[str, IgnoreTracker] = {}
        self.global_languages: set[str] = set()

        self.language_map, self.known_languages = self._parse_config()
        self._code_to_name = {v: k for k, v in self.language_map.items()}

        print(f"Base directory: {self.base_dir}")
        print(f"Translations directory: {self.translations_dir}\n")

    def _default_language_data(self) -> tuple[dict[str, str], set[str]]:
        return dict(self.DEFAULT_LANGUAGE_MAP), set(self.DEFAULT_LANGUAGE_MAP.values())

    def _parse_config(self) -> tuple[dict[str, str], set[str]]:
        config_path = self.translations_dir / "config.txt"

        if not config_path.exists():
            print(f"config.txt not found in {self.translations_dir}, using default language list")
            return self._default_language_data()

        try:
            with open(config_path, "r", encoding="utf-8") as f:
                content = f.read()
        except Exception as e:
            print(f"Failed to read config.txt: {e}, using default language list")
            return self._default_language_data()

        name_to_code = {}

        for line in content.splitlines():
            stripped = line.strip()

            if not stripped or stripped.startswith("//") or stripped in ["{", "}", '"Languages"']:
                continue

            match = re.match(r'^"([^"]+)"\s+"([^"]+)"', stripped)
            if match:
                name_to_code[match.group(1)] = match.group(2)

        if name_to_code:
            print(f"Loaded {len(name_to_code)} language entries from config.txt")
            return name_to_code, set(name_to_code.values())
        else:
            print(f"No languages found in config.txt, using default language list")
            return self._default_language_data()

    def _get_language_display_name(self, code: str) -> str:
        if code in self._code_to_name:
            return f"{code} ({self._code_to_name[code]})"
        return code

    def _add_issue(self, filename: str, line: int, issue_type: str,
                   category: str, message: str, context: Optional[str] = None) -> None:
        if filename in self.ignore_trackers:
            if self.ignore_trackers[filename].is_ignored(line):
                return

        self.issues.append(Issue(
            file=filename,
            line=line,
            issue_type=issue_type,
            category=category,
            message=message,
            context=context
        ))

    def _extract_placeholders(self, value: str) -> set[str]:
        tags = set(re.findall(r'\{([^}]+)\}', value))
        return {
            tag for tag in tags
            if tag.lower() not in self.KNOWN_COLOR_TAGS and not tag.startswith("#")
        }

    def _strip_strings_from_line(self, line: str) -> str:
        result = []
        i = 0
        in_string = False

        while i < len(line):
            char = line[i]

            if char == '\\' and in_string and i + 1 < len(line):
                i += 2
                continue
            elif char == '"':
                in_string = not in_string
                i += 1
                continue
            elif not in_string:
                result.append(char)

            i += 1

        return ''.join(result)

    def lint_all(self) -> list[Issue]:
        if self.translations_dir.exists():
            pattern = "gokz-*.phrases.txt"
            files = sorted(self.translations_dir.glob(pattern))

            if files:
                print(f"Checking {len(files)} translation files in '{self.translations_dir}'...\n")
                for filepath in files:
                    self.lint_file(filepath)
            else:
                print(f"No files matching '{pattern}' found in '{self.translations_dir}'")
        else:
            print(f"Error: Translations directory '{self.translations_dir}' does not exist.")

        for blocks in self.all_phrase_blocks.values():
            for block in blocks:
                if not block.ignored:
                    self.global_languages.update(block.languages.keys())

        self._check_language_consistency()

        return self.issues

    def _read_file_lines(self, filepath: Path, display_name: str) -> Optional[list[str]]:
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                return f.read().splitlines()
        except UnicodeDecodeError:
            self._add_issue(display_name, 0, "error", "Encoding", "File is not valid UTF-8")
        except Exception as e:
            self._add_issue(display_name, 0, "error", "File", f"Could not read file: {e}")
        return None

    def lint_file(self, filepath: Path) -> None:
        lines = self._read_file_lines(filepath, filepath.name)
        if lines is None:
            return

        self.ignore_trackers[filepath.name] = IgnoreTracker(lines)

        phrase_blocks = self._parse_phrases(filepath.name, lines)
        self.all_phrase_blocks[filepath.name] = phrase_blocks
        self._check_basic_format_issues(filepath.name, lines)
        self._check_phrase_format_tags(filepath.name, lines, phrase_blocks)
        self._check_phrase_blocks(filepath.name, phrase_blocks)

    def _parse_format_spec(self, format_value: str) -> set[str]:
        placeholders = set()
        for part in format_value.split(","):
            part = part.strip()
            if ":" in part:
                part = part.split(":")[0].strip()
            if part:
                placeholders.add(part)
        return placeholders

    def _get_valid_placeholders_for_line(self, line_num: int, phrase_blocks: list[PhraseBlock]) -> set[str]:
        for block in phrase_blocks:
            if block.start_line <= line_num <= block.end_line:
                valid = set(block.placeholders)

                if "en" in block.languages:
                    en_value = block.languages["en"][1]
                    en_placeholders = self._extract_placeholders(en_value)
                    valid.update(en_placeholders)

                return valid
        return set()

    def _check_basic_format_issues(self, filename: str, lines: list[str]) -> None:
        brace_stack = []
        prev_line_empty = False

        for line_num, line in enumerate(lines, 1):
            stripped = line.strip()

            if any(x in stripped for x in [IgnoreTracker.IGNORE_START,
                                            IgnoreTracker.IGNORE_END,
                                            IgnoreTracker.IGNORE_NEXT]):
                prev_line_empty = False
                continue

            if line != line.rstrip():
                self._add_issue(
                    filename, line_num, "warning", "Formatting",
                    "Line has trailing whitespace"
                )

            if stripped == "":
                if prev_line_empty:
                    self._add_issue(
                        filename, line_num, "warning", "Formatting",
                        "Multiple consecutive empty lines"
                    )
                prev_line_empty = True
            else:
                prev_line_empty = False

            if stripped.startswith("//"):
                continue

            stripped_no_strings = self._strip_strings_from_line(stripped)

            for char in stripped_no_strings:
                if char == '{':
                    brace_stack.append((line_num, '{'))
                elif char == '}':
                    if not brace_stack:
                        self._add_issue(
                            filename, line_num, "error", "Syntax",
                            "Unmatched closing brace '}'",
                            stripped[:60]
                        )
                    else:
                        brace_stack.pop()

            quote_count = stripped.count('"') - stripped.count('\\"')
            if quote_count % 2 != 0:
                self._add_issue(
                    filename, line_num, "error", "Syntax",
                    "Odd number of quotes - possible unclosed string",
                    stripped[:80]
                )

        for line_num, brace in brace_stack:
            self._add_issue(
                filename, line_num, "error", "Syntax",
                "Unclosed opening brace '{'"
            )

    def _check_phrase_format_tags(self, filename: str, lines: list[str], phrase_blocks: list[PhraseBlock]) -> None:
        for line_num, line in enumerate(lines, 1):
            stripped = line.strip()
            value_match = re.match(r'^\s*"([^"]+)"\s+"(.*)"', stripped)
            if not value_match or value_match.group(1) == "#format":
                continue

            valid_placeholders = self._get_valid_placeholders_for_line(line_num, phrase_blocks)
            value = value_match.group(2)
            for tag in re.findall(r'\{([^}]+)\}', value):
                tag_lower = tag.lower()
                if (tag_lower not in self.KNOWN_COLOR_TAGS and
                    tag not in valid_placeholders and
                    not re.match(r'^\d+$', tag) and
                    not tag.startswith("#")):
                    self._add_issue(
                        filename, line_num, "warning", "Format",
                        f"Unknown format tag: {{{tag}}}",
                        stripped[:80]
                    )

    def _parse_phrases(self, filename: str, lines: list[str]) -> list[PhraseBlock]:
        phrase_blocks = []
        current_block: Optional[PhraseBlock] = None
        brace_depth = 0
        ignore_tracker = self.ignore_trackers.get(filename)

        for line_num, line in enumerate(lines, 1):
            stripped = line.strip()

            if not stripped or stripped.startswith("//"):
                continue

            if stripped == '"Phrases"':
                continue

            if stripped == "{":
                brace_depth += 1
                continue

            if stripped == "}":
                brace_depth -= 1
                if current_block and brace_depth == 1:
                    current_block.end_line = line_num
                    if ignore_tracker and ignore_tracker.is_range_ignored(
                            current_block.start_line, current_block.end_line):
                        current_block.ignored = True
                    phrase_blocks.append(current_block)
                    current_block = None
                continue

            if brace_depth == 1 and stripped.startswith('"') and stripped.endswith('"'):
                phrase_name = stripped[1:-1]
                current_block = PhraseBlock(
                    name=phrase_name,
                    start_line=line_num,
                    end_line=line_num
                )
                continue

            if brace_depth == 2 and current_block:
                match = re.match(r'^"([^"]+)"\s+"(.*)"\s*$', stripped)
                if match:
                    key = match.group(1)
                    value = match.group(2)

                    if key == "#format":
                        current_block.format_spec = value
                        current_block.placeholders = self._parse_format_spec(value)
                    else:
                        if key in current_block.languages:
                            prev_line = current_block.languages[key][0]
                            self._add_issue(
                                filename, line_num, "error", "Duplicate",
                                f"Duplicate language entry '{key}' in phrase '{current_block.name}'",
                                f"First occurrence at line {prev_line}"
                            )
                        else:
                            current_block.languages[key] = (line_num, value)
                else:
                    if stripped and not stripped.startswith("//"):
                        self._add_issue(
                            filename, line_num, "error", "Format",
                            "Line doesn't match expected format: \"key\" \"value\"",
                            stripped[:80]
                        )

        return phrase_blocks

    def _check_phrase_blocks(self, filename: str, blocks: list[PhraseBlock]) -> None:
        phrase_names = {}

        for block in blocks:
            if block.ignored:
                continue

            if block.name in phrase_names:
                self._add_issue(
                    filename, block.start_line, "error", "Duplicate",
                    f"Duplicate phrase name '{block.name}'",
                    f"First occurrence at line {phrase_names[block.name]}"
                )
            else:
                phrase_names[block.name] = block.start_line

            if "en" not in block.languages:
                self._add_issue(
                    filename, block.start_line, "error", "Missing",
                    f"Missing English ('en') translation for phrase '{block.name}'"
                )

            for lang, (line_num, value) in block.languages.items():
                if not value.strip():
                    self._add_issue(
                        filename, line_num, "warning", "Empty",
                        f"Empty translation for language '{lang}' in phrase '{block.name}'"
                    )
                elif value.rstrip().endswith("[...]"):
                    self._add_issue(
                        filename, line_num, "warning", "Truncated",
                        f"Translation appears to be truncated for language '{lang}' in phrase '{block.name}'",
                        value[:60] + "..."
                    )

            if "en" in block.languages:
                en_value = block.languages["en"][1]
                en_placeholders = self._extract_placeholders(en_value)

                for lang, (line_num, value) in block.languages.items():
                    if lang == "en":
                        continue

                    lang_placeholders = self._extract_placeholders(value)
                    missing = en_placeholders - lang_placeholders

                    if missing:
                        self._add_issue(
                            filename, line_num, "error", "Placeholder",
                            f"Missing placeholder(s) {{{', '.join(sorted(missing))}}} in '{lang}' translation for '{block.name}' (present in 'en')"
                        )

    def _check_language_consistency(self) -> None:
        if self.global_languages:
            print(f"Languages found across all files: {sorted(self.global_languages)}\n")

        for filename, blocks in sorted(self.all_phrase_blocks.items()):
            for block in blocks:
                if block.ignored:
                    continue
                for lang in sorted(block.languages.keys()):
                    if lang not in self.known_languages:
                        line_num = block.languages[lang][0]
                        self._add_issue(
                            filename, line_num, "error", "Unknown",
                            f"Unknown language code '{lang}' in phrase '{block.name}' (not in config.txt)"
                        )

    # ==================== REPORTING ====================

    def print_summary(self, output_file: Optional[str] = None) -> None:
        output = StringIO()

        if not self.issues:
            output.write("No issues found!\n")
        else:
            by_file: dict[str, list[Issue]] = defaultdict(list)
            for issue in self.issues:
                by_file[issue.file].append(issue)

            errors = sum(1 for i in self.issues if i.issue_type == "error")
            warnings = sum(1 for i in self.issues if i.issue_type == "warning")

            output.write("=" * 70 + "\n")
            output.write(f"SUMMARY: {errors} error(s), {warnings} warning(s)\n")
            output.write("=" * 70 + "\n")

            for filename in sorted(by_file.keys()):
                issues = by_file[filename]
                file_errors = sum(1 for i in issues if i.issue_type == "error")
                file_warnings = sum(1 for i in issues if i.issue_type == "warning")
                output.write(f"\n{filename} ({file_errors} errors, {file_warnings} warnings)\n")
                output.write("-" * 50 + "\n")
                for issue in sorted(issues, key=lambda x: (x.line, x.message)):
                    output.write(f"  {issue}\n")

            output.write("\n" + "=" * 70 + "\n")
            output.write(f"TOTAL: {errors} error(s), {warnings} warning(s) in {len(by_file)} file(s)\n")
            output.write("=" * 70 + "\n")

        result = output.getvalue()
        print(result, end="")

        if output_file:
            try:
                with open(output_file, "w", encoding="utf-8") as f:
                    f.write(result)
                print(f"Lint results written to: {output_file}")
            except Exception as e:
                print(f"Failed to write lint results to {output_file}: {e}")

    def _collect_missing_data(self) -> tuple[dict, dict, int, int, int]:
        total_missing = 0
        total_phrases = 0
        phrases_with_missing = 0
        missing_per_language: dict[str, int] = defaultdict(int)
        missing_by_file: dict[str, list] = {}

        for filename, blocks in sorted(self.all_phrase_blocks.items()):
            if not blocks:
                continue

            file_missing_report = []

            for block in blocks:
                if block.ignored:
                    continue
                if "en" not in block.languages:
                    continue

                total_phrases += 1
                missing = self.global_languages - set(block.languages.keys())

                if missing:
                    phrases_with_missing += 1
                    sorted_missing = sorted(missing)
                    file_missing_report.append({
                        "phrase": block.name,
                        "line": block.start_line,
                        "missing_languages": sorted_missing,
                        "existing_languages": sorted(block.languages.keys()),
                        "english_text": block.languages.get("en", (0, ""))[1]
                    })

                    for lang in missing:
                        missing_per_language[lang] += 1
                    total_missing += len(missing)

            if file_missing_report:
                missing_by_file[filename] = file_missing_report

        return missing_by_file, dict(missing_per_language), total_missing, total_phrases, phrases_with_missing

    def _get_report_data(self) -> tuple:
        if not hasattr(self, '_cached_report_data'):
            self._cached_report_data = self._collect_missing_data()
        return self._cached_report_data

    @staticmethod
    def _coverage_pct(translated: int, total: int) -> float:
        return (translated / total * 100) if total > 0 else 0

    def generate_missing_languages_report(self, output_file: Optional[str] = None) -> str:
        output = StringIO()
        sorted_languages = sorted(self.global_languages)

        missing_by_file, missing_per_language, total_missing, total_phrases, phrases_with_missing = self._get_report_data()

        output.write("=" * 70 + "\n")
        output.write("MISSING TRANSLATIONS REPORT\n")
        output.write(f"Generated for: {self.base_dir}\n")
        output.write("=" * 70 + "\n\n")

        output.write("SUMMARY\n")
        output.write("-" * 70 + "\n")
        output.write(f"Total languages: {len(self.global_languages)}\n")
        output.write(f"Total phrases: {total_phrases}\n")
        output.write(f"Phrases with missing translations: {phrases_with_missing}\n")
        output.write(f"Total missing translation entries: {total_missing}\n\n")

        output.write("LANGUAGE COVERAGE (Phrases)\n")
        output.write("-" * 70 + "\n\n")

        for lang in sorted_languages:
            missing_count = missing_per_language.get(lang, 0)
            translated = total_phrases - missing_count
            coverage = self._coverage_pct(translated, total_phrases)
            bar_length = int(coverage / 5)
            bar = "█" * bar_length + "░" * (20 - bar_length)
            lang_display = self._get_language_display_name(lang)
            output.write(f"  {lang_display:20} [{bar}] {coverage:5.1f}% ({translated}/{total_phrases})\n")

        output.write("\n")
        output.write(f"Global languages ({len(sorted_languages)}): {', '.join(sorted_languages)}\n")

        output.write("\n" + "=" * 70 + "\n")
        output.write("DETAILED MISSING TRANSLATIONS (Phrases)\n")
        output.write("=" * 70 + "\n")

        for filename, file_report in sorted(missing_by_file.items()):
            output.write(f"\n{filename}\n")
            output.write("-" * 70 + "\n")

            for item in sorted(file_report, key=lambda x: x["line"]):
                output.write(f"  Line {item['line']}: \"{item['phrase']}\"\n")
                output.write(f"    Missing ({len(item['missing_languages'])}): {', '.join(item['missing_languages'])}\n")

        output.write("\n" + "=" * 70 + "\n")

        report_content = output.getvalue()

        if output_file:
            try:
                with open(output_file, "w", encoding="utf-8") as f:
                    f.write(report_content)
                print(f"Missing translations report written to: {output_file}")
            except Exception as e:
                print(f"Failed to write report to {output_file}: {e}")

        return report_content

    def generate_missing_languages_json(self, output_file: Optional[str] = None) -> dict:
        sorted_languages = sorted(self.global_languages)
        missing_by_file, missing_per_language, total_missing, total_phrases, phrases_with_missing = self._get_report_data()

        languages_data = {}
        for lang in sorted_languages:
            missing_count = missing_per_language.get(lang, 0)
            translated = total_phrases - missing_count
            coverage = self._coverage_pct(translated, total_phrases)

            missing_phrases = []
            for filename, file_report in sorted(missing_by_file.items()):
                for item in file_report:
                    if lang in item["missing_languages"]:
                        missing_phrases.append({
                            "file": filename,
                            "phrase": item["phrase"],
                            "line": item["line"],
                            "english_text": item["english_text"]
                        })

            languages_data[lang] = {
                "name": self._code_to_name.get(lang, lang),
                "coverage_percent": round(coverage, 2),
                "translated": translated,
                "missing": missing_count,
                "missing_phrases": missing_phrases
            }

        files_data = {}
        for filename, file_report in sorted(missing_by_file.items()):
            files_data[filename] = {
                "phrases_with_missing": len(file_report),
                "phrases": [
                    {
                        "name": item["phrase"],
                        "line": item["line"],
                        "english_text": item["english_text"],
                        "existing_languages": item["existing_languages"],
                        "missing_languages": item["missing_languages"]
                    }
                    for item in sorted(file_report, key=lambda x: x["line"])
                ]
            }

        json_data = {
            "summary": {
                "total_languages": len(self.global_languages),
                "total_phrases": total_phrases,
                "phrases_with_missing": phrases_with_missing,
                "total_missing_entries": total_missing,
                "all_languages": sorted_languages,
                "known_languages_from_config": sorted(self.known_languages)
            },
            "languages": languages_data,
            "files": files_data
        }

        if output_file:
            try:
                with open(output_file, "w", encoding="utf-8") as f:
                    json.dump(json_data, f, indent=2, ensure_ascii=False)
                print(f"Missing translations JSON written to: {output_file}")
            except Exception as e:
                print(f"Failed to write JSON to {output_file}: {e}")

        return json_data


def main():
    base_dir = sys.argv[1] if len(sys.argv) > 1 else "."

    linter = TranslationLinter(base_dir)
    issues = linter.lint_all()
    linter.print_summary("translation-lint-results.txt")

    linter.generate_missing_languages_report("missing-translations.txt")
    linter.generate_missing_languages_json("missing-translations.json")

    errors = sum(1 for i in issues if i.issue_type == "error")
    sys.exit(1 if errors > 0 else 0)


if __name__ == "__main__":
    main()
