require "crystal-rouge"
require "./asciidoctor_epub/epub_builder"
require "./asciidoctor_epub/xhtml_builder"
require "./asciidoctor_epub/epub_writer"
require "./asciidoctor_epub/converter"

module AsciidoctorEpub
  # Lue au compile-time depuis `shard.yml` via le macro `read_file`.
  # Cf. note mémoire `feedback_shard_version_macro.md` (mémoire ALOLI).
  VERSION = {{
              (read_file("#{__DIR__}/../shard.yml")
                .lines
                .find(&.starts_with?("version:")) || "version: 0.0.0")
                .gsub(/^version:\s*/, "")
                .chomp
            }}

  # Version de la gem Ruby asciidoctor-epub3 utilisée comme référence.
  UPSTREAM_VERSION = "2.3.0"
end
