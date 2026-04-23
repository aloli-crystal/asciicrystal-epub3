require "spec"
require "compress/zip"
require "../../src/asciidoctor_epub"

# Integration-test helpers: run the real converter end-to-end on a
# snippet of AsciiDoc, write an EPUB to a temp path, then read it back
# as a ZIP via the stdlib `Compress::Zip::Reader` to assert on the
# content of the produced XHTML / OPF / NCX entries.
#
# Stays entirely in Crystal — no external `unzip`, `epubcheck` or other
# tool. Each spec asserts the minimal property it cares about (file
# present, body contains expected text, OPF advertises expected metadata,
# etc.).
module IntegrationHelper
  # Converts an AsciiDoc source string to an EPUB on a temp path and
  # returns that path. The caller is responsible for cleanup (usually
  # via `ensure` or by reading the whole archive into memory).
  def self.convert(adoc_source : String) : String
    stem = File.tempname("cae-epub-it")
    adoc_path = stem + ".adoc"
    epub_path = stem + ".epub"
    File.write(adoc_path, adoc_source)

    doc = Asciidoctor.load_file(adoc_path)
    converter = AsciidoctorEpub::Converter.new
    converter.convert_to_file(doc, epub_path)

    File.delete(adoc_path) if File.exists?(adoc_path)
    epub_path
  end

  # Returns the set of entry names (paths inside the zip) for `epub_path`.
  # Handy for asserting the EPUB structure (mimetype, META-INF/container.xml,
  # OEBPS/content.opf, OEBPS/nav.xhtml, chapters, …).
  def self.entries(epub_path : String) : Array(String)
    names = [] of String
    File.open(epub_path, "r") do |file|
      Compress::Zip::Reader.open(file) do |zip|
        zip.each_entry do |entry|
          names << entry.filename
        end
      end
    end
    names
  end

  # Reads a single entry from `epub_path` as a string. Returns nil if
  # the entry is absent.
  def self.read_entry(epub_path : String, entry_name : String) : String?
    result : String? = nil
    File.open(epub_path, "r") do |file|
      Compress::Zip::Reader.open(file) do |zip|
        zip.each_entry do |entry|
          if entry.filename == entry_name
            result = entry.io.gets_to_end
            break
          end
        end
      end
    end
    result
  end

  # Reads every XHTML chapter (`OEBPS/*.xhtml` except `nav.xhtml`) and
  # concatenates their bodies into a single string. Used for `contain?`
  # assertions on the rendered text without caring which chapter holds it.
  def self.chapters_text(epub_path : String) : String
    buf = String::Builder.new
    File.open(epub_path, "r") do |file|
      Compress::Zip::Reader.open(file) do |zip|
        zip.each_entry do |entry|
          next unless entry.filename.starts_with?("OEBPS/") &&
                      entry.filename.ends_with?(".xhtml") &&
                      entry.filename != "OEBPS/nav.xhtml"
          buf << entry.io.gets_to_end
          buf << '\n'
        end
      end
    end
    buf.to_s
  end

  # Quick sanity check: the file exists and is non-empty.
  def self.produces_epub?(adoc_source : String) : Bool
    path = convert(adoc_source)
    ok = File.exists?(path) && File.size(path) > 200
    File.delete(path) if File.exists?(path)
    ok
  end
end
