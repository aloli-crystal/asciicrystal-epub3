require "crystal-rouge"
require "./asciidoctor_epub/epub_builder"
require "./asciidoctor_epub/xhtml_builder"
require "./asciidoctor_epub/epub_writer"
require "./asciidoctor_epub/converter"

module AsciidoctorEpub
  VERSION = "2.3.0.3"

  # Version de la gem Ruby asciidoctor-epub3 utilisée comme référence.
  UPSTREAM_VERSION = "2.3.0"
end
