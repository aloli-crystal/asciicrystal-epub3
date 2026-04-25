require "./spec_helper"

# TOC anchors: the nav.xhtml and toc.ncx entries for sub-sections
# should carry a `#fragment` so EPUB readers jump directly to the
# matching heading inside the chapter, not just to the top of the
# chapter file. The chapter XHTML must in turn carry a matching `id`
# attribute on the section/heading for the anchor to resolve.
describe "Integration · TOC anchors" do
  it "emits matching id attributes on chapter sub-sections in the XHTML" do
    source = <<-ADOC
    = Book

    == Chapter One

    Body of the chapter.

    === Subsection A

    Body of subsection A.

    === Subsection B

    Body of subsection B.
    ADOC
    path = IntegrationHelper.convert(source)
    begin
      text = IntegrationHelper.chapters_text(path)
      # The crystal-asciidoctor parser auto-generates ids for headings
      # (e.g. `_subsection_a`). Both the wrapping <section> and the
      # <hN> heading should carry the id so any fragment-aware reader
      # finds it.
      text.should contain(%(<section id="_subsection_a">))
      text.should contain(%(<section id="_subsection_b">))
      text.should match(/<h2 id="_subsection_a-h">Subsection A<\/h2>/)
      text.should match(/<h2 id="_subsection_b-h">Subsection B<\/h2>/)
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "links sub-section TOC entries to the chapter file with a fragment" do
    source = <<-ADOC
    = Book

    == Chapter One

    Body.

    === Inner Section

    More body.
    ADOC
    path = IntegrationHelper.convert(source)
    begin
      nav = IntegrationHelper.read_entry(path, "OEBPS/nav.xhtml").not_nil!
      # Top-level chapters keep linking to the file root.
      nav.should contain(%(<a href="chapter-1.xhtml">Chapter One</a>))
      # Sub-sections link via the matching anchor inside the chapter.
      nav.should contain(%(<a href="chapter-1.xhtml#_inner_section">Inner Section</a>))
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "writes the same fragment-aware hrefs into toc.ncx" do
    source = <<-ADOC
    = Book

    == Chapter One

    Body.

    === Alpha

    a

    === Beta

    b
    ADOC
    path = IntegrationHelper.convert(source)
    begin
      ncx = IntegrationHelper.read_entry(path, "OEBPS/toc.ncx").not_nil!
      ncx.should contain(%(<content src="chapter-1.xhtml"/>))
      ncx.should contain(%(<content src="chapter-1.xhtml#_alpha"/>))
      ncx.should contain(%(<content src="chapter-1.xhtml#_beta"/>))
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "honours an explicit AsciiDoc id on a sub-section" do
    source = <<-ADOC
    = Book

    == Chapter One

    Body.

    [[overview]]
    === Overview Section

    Hello.
    ADOC
    path = IntegrationHelper.convert(source)
    begin
      nav = IntegrationHelper.read_entry(path, "OEBPS/nav.xhtml").not_nil!
      text = IntegrationHelper.chapters_text(path)
      # Author-supplied id `overview` (not `_overview`) flows through
      # to both the XHTML body and the nav href.
      text.should contain(%(<section id="overview">))
      nav.should contain(%(href="chapter-1.xhtml#overview"))
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "supports nested sub-section TOC anchors recursively" do
    source = <<-ADOC
    = Book

    == Chapter One

    Body.

    === Level 2

    L2 body.

    ==== Level 3

    L3 body.
    ADOC
    path = IntegrationHelper.convert(source)
    begin
      nav = IntegrationHelper.read_entry(path, "OEBPS/nav.xhtml").not_nil!
      nav.should contain(%(href="chapter-1.xhtml#_level_2"))
      nav.should contain(%(href="chapter-1.xhtml#_level_3"))
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end
