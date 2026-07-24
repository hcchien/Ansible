#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'thread'
require 'tmpdir'
require 'uri'

ROOT = File.expand_path('..', __dir__)
SOURCE_LOCALE = File.join(ROOT, 'lib/l10n/app_en.arb')
TARGET_LOCALES = %w[de es fr it ja ko].freeze
ARB_TARGETS = TARGET_LOCALES
CACHE_PATH = File.join(Dir.tmpdir, 'elix-ui-translation-cache.json')
GENERATED_DART = File.join(
  ROOT,
  'lib/l10n/generated_legacy_ui_copy_translations.dart',
)

def dart_files
  Dir.glob(File.join(ROOT, 'lib/**/*.dart')).reject do |path|
    path.end_with?('generated_legacy_ui_copy_translations.dart')
  end
end

def ui_copy_english_strings
  values = {}
  dart_files.each do |path|
    source = File.read(path)
    cursor = 0
    while (start = source.index('.uiCopy(', cursor))
      index = start + 8
      depth = 1
      quote = nil
      escaped = false
      while index < source.length && depth.positive?
        char = source[index]
        if quote
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            quote = nil
          end
        elsif char == "'" || char == '"'
          quote = char
        elsif char == '('
          depth += 1
        elsif char == ')'
          depth -= 1
        end
        index += 1
      end

      call = source[start...index]
      match = call.match(
        /\ben\s*:\s*((?:(?:'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")\s*)+)/m,
      )
      if match && !match[1].include?('$')
        chunks = match[1].scan(
          /'((?:\\.|[^'\\])*)'|"((?:\\.|[^"\\])*)"/m,
        ).map { |single, double| single || double }
        value = chunks.join
          .gsub('\\n', "\n")
          .gsub("\\'", "'")
          .gsub('\\"', '"')
          .gsub('\\\\', '\\')
        values[value] = true unless value.empty?
      end
      cursor = index
    end
  end
  values.keys.sort
end

def ui_copy_dynamic_templates
  templates = {}
  dart_files.each do |path|
    source = File.read(path)
    cursor = 0
    while (start = source.index('.uiCopy(', cursor))
      index = start + 8
      depth = 1
      quote = nil
      escaped = false
      while index < source.length && depth.positive?
        char = source[index]
        if quote
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            quote = nil
          end
        elsif char == "'" || char == '"'
          quote = char
        elsif char == '('
          depth += 1
        elsif char == ')'
          depth -= 1
        end
        index += 1
      end

      call = source[start...index]
      match = call.match(
        /\ben\s*:\s*((?:(?:'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")\s*)+)/m,
      )
      if match && match[1].include?('$')
        chunks = match[1].scan(
          /'((?:\\.|[^'\\])*)'|"((?:\\.|[^"\\])*)"/m,
        ).map { |single, double| single || double }
        raw = chunks.join
          .gsub('\\n', "\n")
          .gsub("\\'", "'")
          .gsub('\\"', '"')
          .gsub('\\\\', '\\')
        argument_index = 0
        template = raw.gsub(/\$\{[^{}]+\}|\$[A-Za-z_]\w*/) do
          token = "ELIXARG#{argument_index}TOKEN"
          argument_index += 1
          token
        end
        templates[template] = argument_index if argument_index.positive?
      end
      cursor = index
    end
  end
  templates
end

def load_cache
  return {} unless File.exist?(CACHE_PATH)

  JSON.parse(File.read(CACHE_PATH))
rescue JSON::ParserError
  {}
end

def protect_placeholders(text)
  placeholders = []
  protected = text.gsub(/\{[^{}]+\}/) do |placeholder|
    token = "ELIXPH#{placeholders.length}TOKEN"
    placeholders << placeholder
    token
  end
  [protected, placeholders]
end

def restore_placeholders(text, placeholders)
  placeholders.each_with_index.reduce(text) do |result, (placeholder, index)|
    result.gsub(/ELIXPH\s*#{index}\s*TOKEN/i, placeholder)
  end
end

def google_translate(text, target)
  protected, placeholders = protect_placeholders(text)
  uri = URI('https://translate.googleapis.com/translate_a/single')
  uri.query = URI.encode_www_form(
    client: 'gtx',
    sl: 'en',
    tl: target,
    dt: 't',
    q: protected,
  )
  response = Net::HTTP.get_response(uri)
  raise "translation failed (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

  translated = JSON.parse(response.body).fetch(0).map { |part| part.fetch(0) }.join
  restore_placeholders(translated, placeholders)
end

def translate_all(strings)
  cache = load_cache
  jobs = Queue.new
  TARGET_LOCALES.each do |locale|
    strings.each do |english|
      key = "#{locale}\u0000#{english}"
      jobs << [locale, english, key] unless cache.key?(key)
    end
  end

  mutex = Mutex.new
  failures = Queue.new
  workers = Array.new(12) do
    Thread.new do
      loop do
        locale, english, key = jobs.pop(true)
        translated = google_translate(english, locale)
        mutex.synchronize { cache[key] = translated }
      rescue ThreadError
        break
      rescue StandardError => error
        failures << [locale, english, error.message]
      end
    end
  end
  workers.each(&:join)

  unless failures.empty?
    details = []
    details << failures.pop until failures.empty?
    raise "translation failures:\n#{details.first(20).inspect}"
  end

  File.write(CACHE_PATH, JSON.pretty_generate(cache))
  cache
end

def update_arbs(cache)
  source = JSON.parse(File.read(SOURCE_LOCALE))
  ARB_TARGETS.each do |locale|
    target_path = File.join(ROOT, "lib/l10n/app_#{locale}.arb")
    target = JSON.parse(File.read(target_path))
    source.each do |key, english|
      next if key.start_with?('@')
      next unless english.is_a?(String)

      target[key] = cache.fetch("#{locale}\u0000#{english}") unless target.key?(key)
    end
    source.each do |key, metadata|
      target[key] = metadata if key.start_with?('@')
    end
    ordered = { '@@locale' => locale }
    source.each_key { |key| ordered[key] = target.fetch(key) unless key == '@@locale' }
    File.write(target_path, "#{JSON.pretty_generate(ordered)}\n")
  end
end

def dart_string(value)
  JSON.generate(value)
    .gsub('$', '\\$')
    .gsub("\u2028", '\\u2028')
    .gsub("\u2029", '\\u2029')
end

def write_generated_dart(strings, dynamic_templates, cache)
  output = +"// Generated by tool/generate_ui_translations.rb. Do not edit.\n"
  output << "const generatedLegacyUiCopyTranslations = <String, Map<String, String>>{\n"
  TARGET_LOCALES.each do |locale|
    output << "  #{dart_string(locale)}: {\n"
    strings.each do |english|
      translated = cache.fetch("#{locale}\u0000#{english}")
      output << "    #{dart_string(english)}: #{dart_string(translated)},\n"
    end
    output << "  },\n"
  end
  output << "};\n"
  output << <<~'DART'

    final generatedLegacyUiCopyPatterns =
        <String, List<GeneratedLegacyUiCopyPattern>>{
  DART
  TARGET_LOCALES.each do |locale|
    output << "  #{dart_string(locale)}: [\n"
    dynamic_templates.each do |template, argument_count|
      pattern = Regexp.escape(template)
      argument_count.times do |index|
        pattern = pattern.sub(Regexp.escape("ELIXARG#{index}TOKEN"), '(.*?)')
      end
      translated = cache.fetch("#{locale}\u0000#{template}")
      output << "    GeneratedLegacyUiCopyPattern(\n"
      output << "      RegExp(#{dart_string("^#{pattern}$")}),\n"
      output << "      #{dart_string(translated)},\n"
      output << "      #{argument_count},\n"
      output << "    ),\n"
    end
    output << "  ],\n"
  end
  output << <<~'DART'
    };

    final class GeneratedLegacyUiCopyPattern {
      const GeneratedLegacyUiCopyPattern(
        this.pattern,
        this.translationTemplate,
        this.argumentCount,
      );

      final RegExp pattern;
      final String translationTemplate;
      final int argumentCount;

      String? apply(String value) {
        final match = pattern.firstMatch(value);
        if (match == null) return null;
        var translated = translationTemplate;
        for (var index = 0; index < argumentCount; index += 1) {
          translated = translated.replaceAll(
            'ELIXARG${index}TOKEN',
            match.group(index + 1) ?? '',
          );
        }
        return translated;
      }
    }

    String? generatedLocalizeLegacyUiCopyPattern(
      String locale,
      String english,
    ) {
      for (final pattern
          in generatedLegacyUiCopyPatterns[locale] ??
              const <GeneratedLegacyUiCopyPattern>[]) {
        final translated = pattern.apply(english);
        if (translated != null) return translated;
      }
      return null;
    }
  DART
  File.write(GENERATED_DART, output)
end

arb_source = JSON.parse(File.read(SOURCE_LOCALE))
arb_strings = arb_source.values.select { |value| value.is_a?(String) }
legacy_strings = ui_copy_english_strings
dynamic_templates = ui_copy_dynamic_templates
all_strings = (arb_strings + legacy_strings + dynamic_templates.keys).uniq.sort
cache = translate_all(all_strings)
update_arbs(cache)
write_generated_dart(legacy_strings, dynamic_templates, cache)

warn "Translated #{arb_strings.length} ARB values and " \
     "#{legacy_strings.length} fixed / #{dynamic_templates.length} dynamic " \
     "legacy UI values into #{TARGET_LOCALES.length} locales."
