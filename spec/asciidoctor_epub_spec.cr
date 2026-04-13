require "./spec_helper"

describe AsciidoctorEpub::EpubBuilder do
  it "generates valid container.xml" do
    builder = AsciidoctorEpub::EpubBuilder.new
    xml = builder.container_xml
    xml.should contain("application/oebps-package+xml")
    xml.should contain("OEBPS/content.opf")
  end

  it "generates content.opf with metadata" do
    builder = AsciidoctorEpub::EpubBuilder.new
    builder.title = "Test Book"
    builder.authors = ["John Doe"]
    builder.language = "fr"
    builder.add_chapter("ch1", "Chapter 1", "chapter-1.xhtml", "<p>Hello</p>")

    opf = builder.content_opf
    opf.should contain("<dc:title>Test Book</dc:title>")
    opf.should contain("<dc:creator>John Doe</dc:creator>")
    opf.should contain("<dc:language>fr</dc:language>")
    opf.should contain("id=\"ch1\"")
    opf.should contain("href=\"chapter-1.xhtml\"")
    opf.should contain("idref=\"ch1\"")
  end

  it "generates toc.ncx with navigation points" do
    builder = AsciidoctorEpub::EpubBuilder.new
    builder.title = "Test Book"
    builder.add_chapter("ch1", "Chapter 1", "chapter-1.xhtml", "")
    builder.add_chapter("ch2", "Chapter 2", "chapter-2.xhtml", "")

    ncx = builder.toc_ncx
    ncx.should contain("<text>Test Book</text>")
    ncx.should contain("<text>Chapter 1</text>")
    ncx.should contain("<text>Chapter 2</text>")
    ncx.should contain("playOrder=\"1\"")
    ncx.should contain("playOrder=\"2\"")
  end

  it "generates nav.xhtml with links" do
    builder = AsciidoctorEpub::EpubBuilder.new
    builder.title = "Test Book"
    builder.add_chapter("ch1", "Chapter 1", "chapter-1.xhtml", "")

    nav = builder.nav_xhtml
    nav.should contain("epub:type=\"toc\"")
    nav.should contain("<a href=\"chapter-1.xhtml\">Chapter 1</a>")
  end

  it "generates unique identifier" do
    b1 = AsciidoctorEpub::EpubBuilder.new
    b2 = AsciidoctorEpub::EpubBuilder.new
    b1.identifier.should_not eq(b2.identifier)
  end

  it "includes cover image in manifest" do
    builder = AsciidoctorEpub::EpubBuilder.new
    builder.cover_image = "images/cover.jpg"
    opf = builder.content_opf
    opf.should contain("cover-image")
    opf.should contain("images/cover.jpg")
    opf.should contain("image/jpeg")
  end
end

describe AsciidoctorEpub::XhtmlBuilder do
  it "wraps content in valid XHTML5" do
    xhtml = AsciidoctorEpub::XhtmlBuilder.wrap("Test", "<p>Hello</p>")
    xhtml.should contain("<?xml version=\"1.0\"")
    xhtml.should contain("<!DOCTYPE html>")
    xhtml.should contain("xmlns=\"http://www.w3.org/1999/xhtml\"")
    xhtml.should contain("<title>Test</title>")
    xhtml.should contain("<p>Hello</p>")
  end

  it "generates a cover page" do
    xhtml = AsciidoctorEpub::XhtmlBuilder.cover_page("My Book", "images/cover.jpg")
    xhtml.should contain("epub:type=\"cover\"")
    xhtml.should contain("images/cover.jpg")
  end

  it "generates a title page" do
    xhtml = AsciidoctorEpub::XhtmlBuilder.title_page("My Book", ["Author One", "Author Two"])
    xhtml.should contain("epub:type=\"titlepage\"")
    xhtml.should contain("<h1>My Book</h1>")
    xhtml.should contain("Author One")
    xhtml.should contain("Author Two")
  end
end

describe AsciidoctorEpub::EpubWriter do
  it "writes a valid EPUB to IO" do
    builder = AsciidoctorEpub::EpubBuilder.new
    builder.title = "Test"
    builder.add_chapter("ch1", "Chapter 1", "chapter-1.xhtml",
      AsciidoctorEpub::XhtmlBuilder.wrap("Chapter 1", "<p>Content</p>"))

    bytes = AsciidoctorEpub::EpubWriter.new(builder).to_bytes
    bytes.size.should be > 0

    # Verify it's a valid ZIP (starts with PK)
    bytes[0].should eq(0x50) # P
    bytes[1].should eq(0x4B) # K
  end

  it "writes EPUB to file" do
    builder = AsciidoctorEpub::EpubBuilder.new
    builder.title = "Test"
    builder.add_chapter("ch1", "Chapter 1", "chapter-1.xhtml",
      AsciidoctorEpub::XhtmlBuilder.wrap("Chapter 1", "<p>Content</p>"))

    Dir.mkdir_p("spec/output")
    path = "spec/output/test.epub"
    AsciidoctorEpub::EpubWriter.new(builder).write(path)

    File.exists?(path).should be_true
    File.size(path).should be > 0
  ensure
    File.delete("spec/output/test.epub") if File.exists?("spec/output/test.epub")
  end
end

describe AsciidoctorEpub::Converter do
  it "converts a simple AsciiDoc document to EPUB bytes" do
    input = <<-ADOC
    = My Book
    Author Name

    == Chapter 1

    This is the first chapter.

    == Chapter 2

    This is the second chapter with *bold* and _italic_.
    ADOC

    doc = Asciidoctor.load(input)
    bytes = AsciidoctorEpub::Converter.new.convert(doc)

    bytes.size.should be > 0
    bytes[0].should eq(0x50) # P
    bytes[1].should eq(0x4B) # K
  end

  it "converts a document with lists" do
    input = <<-ADOC
    = My Book

    == Lists

    * Item 1
    * Item 2
    * Item 3
    ADOC

    doc = Asciidoctor.load(input)
    bytes = AsciidoctorEpub::Converter.new.convert(doc)
    bytes.size.should be > 0
  end

  it "converts a document with code blocks" do
    input = <<-ADOC
    = My Book

    == Code

    [source,crystal]
    ----
    puts "Hello, World!"
    ----
    ADOC

    doc = Asciidoctor.load(input)
    bytes = AsciidoctorEpub::Converter.new.convert(doc)
    bytes.size.should be > 0
  end

  it "produces syntax-highlighted output for source code blocks" do
    input = <<-ADOC
    = My Book

    == Code

    [source,crystal]
    ----
    def hello
      puts "Hello, World!"
    end
    ----
    ADOC

    doc = Asciidoctor.load(input)
    bytes = AsciidoctorEpub::Converter.new.convert(doc)

    # Extract chapter XHTML from the EPUB ZIP
    chapter_xhtml = ""
    io = IO::Memory.new(bytes)
    Compress::Zip::Reader.open(io) do |zip|
      zip.each_entry do |entry|
        if entry.filename.ends_with?("chapter-1.xhtml")
          chapter_xhtml = entry.io.gets_to_end
        end
      end
    end

    chapter_xhtml.should_not be_empty
    # Should contain Rouge syntax highlighting spans (e.g. .k for keyword, .s for string)
    chapter_xhtml.should contain(%(<pre class="highlight"><code data-lang="crystal">))
    chapter_xhtml.should contain(%(<span class="))
    # "def" is a keyword, should produce a .k or .kd span
    (chapter_xhtml.includes?("<span class=\"k\">") || chapter_xhtml.includes?("<span class=\"kd\">")).should be_true
  end

  it "converts a document without sections" do
    input = "Just a simple paragraph."
    doc = Asciidoctor.load(input)
    bytes = AsciidoctorEpub::Converter.new.convert(doc)
    bytes.size.should be > 0
  end

  it "writes EPUB to file" do
    input = <<-ADOC
    = Test Book
    Test Author
    :lang: fr

    == Introduction

    Un paragraphe en français.

    == Chapitre 2

    Un autre chapitre.
    ADOC

    Dir.mkdir_p("spec/output")
    path = "spec/output/test_converter.epub"
    doc = Asciidoctor.load(input)
    AsciidoctorEpub::Converter.new.convert_to_file(doc, path)

    File.exists?(path).should be_true
    File.size(path).should be > 0
  ensure
    File.delete("spec/output/test_converter.epub") if File.exists?("spec/output/test_converter.epub")
  end

  it "extracts metadata from document" do
    input = <<-ADOC
    = Mon Livre
    Jean Dupont
    :lang: fr
    :description: Un livre de test

    == Chapitre 1

    Contenu.
    ADOC

    doc = Asciidoctor.load(input)
    bytes = AsciidoctorEpub::Converter.new.convert(doc)
    bytes.size.should be > 0
  end
end
