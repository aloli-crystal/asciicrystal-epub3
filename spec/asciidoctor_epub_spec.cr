require "./spec_helper"

describe AsciicrystalEpub::EpubBuilder do
  it "generates valid container.xml" do
    builder = AsciicrystalEpub::EpubBuilder.new
    xml = builder.container_xml
    xml.should contain("application/oebps-package+xml")
    xml.should contain("OEBPS/content.opf")
  end

  it "generates content.opf with metadata" do
    builder = AsciicrystalEpub::EpubBuilder.new
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
    builder = AsciicrystalEpub::EpubBuilder.new
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
    builder = AsciicrystalEpub::EpubBuilder.new
    builder.title = "Test Book"
    builder.add_chapter("ch1", "Chapter 1", "chapter-1.xhtml", "")

    nav = builder.nav_xhtml
    nav.should contain("epub:type=\"toc\"")
    nav.should contain("<a href=\"chapter-1.xhtml\">Chapter 1</a>")
  end

  it "generates unique identifier" do
    b1 = AsciicrystalEpub::EpubBuilder.new
    b2 = AsciicrystalEpub::EpubBuilder.new
    b1.identifier.should_not eq(b2.identifier)
  end

  it "includes cover image in manifest" do
    builder = AsciicrystalEpub::EpubBuilder.new
    builder.cover_image = "images/cover.jpg"
    opf = builder.content_opf
    opf.should contain("cover-image")
    opf.should contain("images/cover.jpg")
    opf.should contain("image/jpeg")
  end

  it "generates hierarchical nav.xhtml with nested sections" do
    builder = AsciicrystalEpub::EpubBuilder.new
    builder.title = "Test Book"

    children = [
      AsciicrystalEpub::EpubBuilder::TocEntry.new("Section 1.1", "sec-1-1", [] of AsciicrystalEpub::EpubBuilder::TocEntry),
      AsciicrystalEpub::EpubBuilder::TocEntry.new("Section 1.2", "sec-1-2", [
        AsciicrystalEpub::EpubBuilder::TocEntry.new("Section 1.2.1", "sec-1-2-1", [] of AsciicrystalEpub::EpubBuilder::TocEntry),
      ]),
    ]
    builder.add_chapter("ch1", "Chapter 1", "chapter-1.xhtml", "", children)

    nav = builder.nav_xhtml
    # Top-level chapter still links to the file root
    nav.should contain("<a href=\"chapter-1.xhtml\">Chapter 1</a>")
    # Sub-section entries now link to the parent file with a fragment
    # anchor, so the EPUB reader scrolls to the matching heading.
    nav.should contain("<a href=\"chapter-1.xhtml#sec-1-1\">Section 1.1</a>")
    nav.should contain("<a href=\"chapter-1.xhtml#sec-1-2\">Section 1.2</a>")
    nav.should contain("<a href=\"chapter-1.xhtml#sec-1-2-1\">Section 1.2.1</a>")
    # Should have nested <ol> elements
    nav.scan(/<ol>/).size.should be >= 2
  end

  it "generates hierarchical toc.ncx with nested navPoints" do
    builder = AsciicrystalEpub::EpubBuilder.new
    builder.title = "Test Book"

    children = [
      AsciicrystalEpub::EpubBuilder::TocEntry.new("Section 1.1", "sec-1-1", [] of AsciicrystalEpub::EpubBuilder::TocEntry),
    ]
    builder.add_chapter("ch1", "Chapter 1", "chapter-1.xhtml", "", children)

    ncx = builder.toc_ncx
    ncx.should contain("<text>Chapter 1</text>")
    ncx.should contain("<text>Section 1.1</text>")
    # Depth should reflect the hierarchy
    ncx.should contain("dtb:depth")
    ncx.should contain("content=\"2\"")
    # Should have nested navPoint
    ncx.scan(/navPoint/).size.should be >= 4 # opening + closing for 2 navPoints
  end

  it "includes resources in manifest" do
    builder = AsciicrystalEpub::EpubBuilder.new
    builder.add_resource("img-photo", "images/photo.png", "image/png")
    opf = builder.content_opf
    opf.should contain("id=\"img-photo\"")
    opf.should contain("href=\"images/photo.png\"")
    opf.should contain("media-type=\"image/png\"")
  end
end

describe AsciicrystalEpub::XhtmlBuilder do
  it "wraps content in valid XHTML5" do
    xhtml = AsciicrystalEpub::XhtmlBuilder.wrap("Test", "<p>Hello</p>")
    xhtml.should contain("<?xml version=\"1.0\"")
    xhtml.should contain("<!DOCTYPE html>")
    xhtml.should contain("xmlns=\"http://www.w3.org/1999/xhtml\"")
    xhtml.should contain("<title>Test</title>")
    xhtml.should contain("<p>Hello</p>")
  end

  it "generates a cover page" do
    xhtml = AsciicrystalEpub::XhtmlBuilder.cover_page("My Book", "images/cover.jpg")
    xhtml.should contain("epub:type=\"cover\"")
    xhtml.should contain("images/cover.jpg")
  end

  it "generates a title page" do
    xhtml = AsciicrystalEpub::XhtmlBuilder.title_page("My Book", ["Author One", "Author Two"])
    xhtml.should contain("epub:type=\"titlepage\"")
    xhtml.should contain("<h1>My Book</h1>")
    xhtml.should contain("Author One")
    xhtml.should contain("Author Two")
  end
end

describe AsciicrystalEpub::EpubWriter do
  it "writes a valid EPUB to IO" do
    builder = AsciicrystalEpub::EpubBuilder.new
    builder.title = "Test"
    builder.add_chapter("ch1", "Chapter 1", "chapter-1.xhtml",
      AsciicrystalEpub::XhtmlBuilder.wrap("Chapter 1", "<p>Content</p>"))

    bytes = AsciicrystalEpub::EpubWriter.new(builder).to_bytes
    bytes.size.should be > 0

    # Verify it's a valid ZIP (starts with PK)
    bytes[0].should eq(0x50) # P
    bytes[1].should eq(0x4B) # K
  end

  it "writes EPUB to file" do
    builder = AsciicrystalEpub::EpubBuilder.new
    builder.title = "Test"
    builder.add_chapter("ch1", "Chapter 1", "chapter-1.xhtml",
      AsciicrystalEpub::XhtmlBuilder.wrap("Chapter 1", "<p>Content</p>"))

    Dir.mkdir_p("spec/output")
    path = "spec/output/test.epub"
    AsciicrystalEpub::EpubWriter.new(builder).write(path)

    File.exists?(path).should be_true
    File.size(path).should be > 0
  ensure
    File.delete("spec/output/test.epub") if File.exists?("spec/output/test.epub")
  end

  it "embeds image files in the ZIP" do
    # Create a temporary test image
    Dir.mkdir_p("spec/output")
    test_image_path = "spec/output/test_image.png"
    File.write(test_image_path, "FAKE_PNG_DATA")

    builder = AsciicrystalEpub::EpubBuilder.new
    builder.title = "Test"
    builder.add_chapter("ch1", "Chapter 1", "chapter-1.xhtml",
      AsciicrystalEpub::XhtmlBuilder.wrap("Chapter 1", "<p>Content</p>"))

    image_files = {"images/test_image.png" => test_image_path}
    bytes = AsciicrystalEpub::EpubWriter.new(builder, image_files).to_bytes

    # Verify the image is in the ZIP
    found_image = false
    io = IO::Memory.new(bytes)
    Compress::Zip::Reader.open(io) do |zip|
      zip.each_entry do |entry|
        if entry.filename == "OEBPS/images/test_image.png"
          found_image = true
          entry.io.gets_to_end.should eq("FAKE_PNG_DATA")
        end
      end
    end
    found_image.should be_true
  ensure
    File.delete("spec/output/test_image.png") if File.exists?("spec/output/test_image.png")
  end
end

describe AsciicrystalEpub::Converter do
  it "converts a simple AsciiDoc document to EPUB bytes" do
    input = <<-ADOC
    = My Book
    Author Name

    == Chapter 1

    This is the first chapter.

    == Chapter 2

    This is the second chapter with *bold* and _italic_.
    ADOC

    doc = Asciicrystal.load(input)
    bytes = AsciicrystalEpub::Converter.new.convert(doc)

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

    doc = Asciicrystal.load(input)
    bytes = AsciicrystalEpub::Converter.new.convert(doc)
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

    doc = Asciicrystal.load(input)
    bytes = AsciicrystalEpub::Converter.new.convert(doc)
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

    doc = Asciicrystal.load(input)
    bytes = AsciicrystalEpub::Converter.new.convert(doc)

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
    doc = Asciicrystal.load(input)
    bytes = AsciicrystalEpub::Converter.new.convert(doc)
    bytes.size.should be > 0
  end

  it "writes EPUB to file" do
    input = <<-ADOC
    = Test Book
    Test Author
    :lang: fr

    == Introduction

    Un paragraphe en francais.

    == Chapitre 2

    Un autre chapitre.
    ADOC

    Dir.mkdir_p("spec/output")
    path = "spec/output/test_converter.epub"
    doc = Asciicrystal.load(input)
    AsciicrystalEpub::Converter.new.convert_to_file(doc, path)

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

    doc = Asciicrystal.load(input)
    bytes = AsciicrystalEpub::Converter.new.convert(doc)
    bytes.size.should be > 0
  end

  it "converts a document with description lists" do
    input = <<-ADOC
    = My Book

    == Glossary

    CPU:: Central Processing Unit
    RAM:: Random Access Memory
    SSD:: Solid State Drive
    ADOC

    doc = Asciicrystal.load(input)
    bytes = AsciicrystalEpub::Converter.new.convert(doc)

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
    chapter_xhtml.should contain("<dl>")
    chapter_xhtml.should contain("<dt>")
    chapter_xhtml.should contain("<dd>")
    chapter_xhtml.should contain("</dl>")
  end

  it "converts a document with images and tracks them as resources" do
    input = <<-ADOC
    = My Book

    == Chapter with Image

    image::photo.png[A photo]
    ADOC

    doc = Asciicrystal.load(input)
    bytes = AsciicrystalEpub::Converter.new.convert(doc)

    # Extract chapter XHTML from the EPUB ZIP
    chapter_xhtml = ""
    opf_content = ""
    io = IO::Memory.new(bytes)
    Compress::Zip::Reader.open(io) do |zip|
      zip.each_entry do |entry|
        if entry.filename.ends_with?("chapter-1.xhtml")
          chapter_xhtml = entry.io.gets_to_end
        end
        if entry.filename.ends_with?("content.opf")
          opf_content = entry.io.gets_to_end
        end
      end
    end

    chapter_xhtml.should contain("images/photo.png")
    chapter_xhtml.should contain("<figure>")
    # OPF manifest should include the image resource
    opf_content.should contain("images/photo.png")
    opf_content.should contain("image/png")
  end

  it "generates hierarchical TOC for nested sections" do
    input = <<-ADOC
    = My Book

    == Chapter 1

    Intro.

    === Section 1.1

    Content of section 1.1.

    === Section 1.2

    Content of section 1.2.

    == Chapter 2

    More content.
    ADOC

    doc = Asciicrystal.load(input)
    bytes = AsciicrystalEpub::Converter.new.convert(doc)

    nav_xhtml = ""
    ncx_content = ""
    io = IO::Memory.new(bytes)
    Compress::Zip::Reader.open(io) do |zip|
      zip.each_entry do |entry|
        if entry.filename.ends_with?("nav.xhtml")
          nav_xhtml = entry.io.gets_to_end
        end
        if entry.filename.ends_with?("toc.ncx")
          ncx_content = entry.io.gets_to_end
        end
      end
    end

    # NAV should have nested ol for sub-sections
    nav_xhtml.should contain("Section 1.1")
    nav_xhtml.should contain("Section 1.2")
    nav_xhtml.scan(/<ol>/).size.should be >= 2

    # NCX should have nested navPoints
    ncx_content.should contain("Section 1.1")
    ncx_content.should contain("Section 1.2")
  end

  it "handles cover page when front-cover-image attribute is set" do
    # Create a temporary cover image
    Dir.mkdir_p("spec/output")
    File.write("spec/output/cover.jpg", "FAKE_JPEG")

    input = <<-ADOC
    = My Book
    Author Name
    :front-cover-image: image:cover.jpg[]

    == Chapter 1

    Content.
    ADOC

    doc = Asciicrystal.load(input, {"base_dir" => "spec/output"})
    bytes = AsciicrystalEpub::Converter.new.convert(doc)

    cover_xhtml = ""
    opf_content = ""
    found_cover_image = false
    io = IO::Memory.new(bytes)
    Compress::Zip::Reader.open(io) do |zip|
      zip.each_entry do |entry|
        if entry.filename.ends_with?("cover.xhtml")
          cover_xhtml = entry.io.gets_to_end
        end
        if entry.filename.ends_with?("content.opf")
          opf_content = entry.io.gets_to_end
        end
        if entry.filename == "OEBPS/images/cover.jpg"
          found_cover_image = true
          entry.io.gets_to_end.should eq("FAKE_JPEG")
        end
      end
    end

    cover_xhtml.should contain("epub:type=\"cover\"")
    cover_xhtml.should contain("images/cover.jpg")
    opf_content.should contain("cover-image")
    found_cover_image.should be_true
  ensure
    File.delete("spec/output/cover.jpg") if File.exists?("spec/output/cover.jpg")
  end

  it "converts a document with footnotes" do
    input = <<-ADOC
    = My Book

    == Chapter 1

    This has a footnote.footnote:[This is the footnote text.]
    ADOC

    doc = Asciicrystal.load(input)
    bytes = AsciicrystalEpub::Converter.new.convert(doc)

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
    # Should contain footnotes section
    chapter_xhtml.should contain("footnotes")
  end
end
