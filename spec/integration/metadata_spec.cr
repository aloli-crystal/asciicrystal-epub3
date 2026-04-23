require "./spec_helper"

# Metadata round-trip: the AsciiDoc doctitle, :author: and :lang: end
# up in the correct Dublin Core elements inside `OEBPS/content.opf`.
# If this spec regresses, readers like Apple Books, Calibre or Thorium
# will display the wrong book title / author.
describe "Integration · EPUB metadata" do
  it "puts the document title in <dc:title>" do
    source = <<-ADOC
    = Le Guide du Voyageur
    :author: Douglas Adams
    :lang: fr

    Don't panic.
    ADOC
    path = IntegrationHelper.convert(source)
    begin
      opf = IntegrationHelper.read_entry(path, "OEBPS/content.opf").not_nil!
      opf.should contain("<dc:title>Le Guide du Voyageur</dc:title>")
      opf.should contain("<dc:creator>Douglas Adams</dc:creator>")
      opf.should contain("<dc:language>fr</dc:language>")
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "advertises the chapters in the OPF spine" do
    source = <<-ADOC
    = Book

    == Chapter One

    Para 1.

    == Chapter Two

    Para 2.
    ADOC
    path = IntegrationHelper.convert(source)
    begin
      opf = IntegrationHelper.read_entry(path, "OEBPS/content.opf").not_nil!
      # Both chapters should be declared in the manifest + spine.
      opf.should contain(%(href="chapter-1.xhtml"))
      opf.should contain(%(href="chapter-2.xhtml"))
      opf.should contain(%(idref="chapter-1"))
      opf.should contain(%(idref="chapter-2"))
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "lists chapters in nav.xhtml for EPUB3 navigation" do
    source = <<-ADOC
    = Book

    == First

    Hello.

    == Second

    Bye.
    ADOC
    path = IntegrationHelper.convert(source)
    begin
      nav = IntegrationHelper.read_entry(path, "OEBPS/nav.xhtml").not_nil!
      nav.should contain(%(epub:type="toc"))
      nav.should contain("First")
      nav.should contain("Second")
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "lists chapters in toc.ncx for EPUB2 fallback" do
    source = <<-ADOC
    = Book

    == Alpha

    a

    == Beta

    b
    ADOC
    path = IntegrationHelper.convert(source)
    begin
      ncx = IntegrationHelper.read_entry(path, "OEBPS/toc.ncx").not_nil!
      ncx.should contain("<text>Alpha</text>")
      ncx.should contain("<text>Beta</text>")
      ncx.should contain(%(playOrder="1"))
      ncx.should contain(%(playOrder="2"))
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end
