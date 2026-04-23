require "./spec_helper"

# Baseline check: the converter runs end-to-end on the simplest possible
# input and produces a non-empty EPUB file.
describe "Integration · sanity" do
  it "produces a non-empty .epub for a trivial document" do
    IntegrationHelper.produces_epub?("= Hello\n\nWorld.\n").should be_true
  end

  it "ships the mandatory EPUB skeleton entries" do
    path = IntegrationHelper.convert("= Hello\n\nWorld.\n")
    begin
      names = IntegrationHelper.entries(path)
      # The EPUB spec requires:
      #   - `mimetype` at the root
      #   - `META-INF/container.xml`
      # Our writer also emits a content.opf, a toc.ncx and a nav.xhtml
      # inside OEBPS/, all of which are conventional for EPUB3.
      names.should contain("mimetype")
      names.should contain("META-INF/container.xml")
      names.should contain("OEBPS/content.opf")
      names.should contain("OEBPS/toc.ncx")
      names.should contain("OEBPS/nav.xhtml")
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "declares the expected EPUB MIME type" do
    path = IntegrationHelper.convert("= Hello\n\nWorld.\n")
    begin
      mime = IntegrationHelper.read_entry(path, "mimetype")
      mime.should eq("application/epub+zip")
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end
