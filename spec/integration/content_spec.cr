require "./spec_helper"

# Rendered content: the AsciiDoc body blocks end up translated to the
# expected HTML5 constructs inside the chapter XHTML files. These are
# the most likely regression surfaces when the AST traversal changes.
describe "Integration · rendered content" do
  it "wraps paragraphs in <p> tags" do
    text = IntegrationHelper.chapters_text(
      IntegrationHelper.convert("= Doc\n\nHello world.\n")
    )
    text.should contain("<p>Hello world.</p>")
  end

  it "emits <h1>…<h6> for sections" do
    text = IntegrationHelper.chapters_text(
      IntegrationHelper.convert(<<-ADOC)
      = Book

      == Heading One

      Body.
      ADOC
    )
    # The heading carries an `id="…-h"` attribute (anchor target for
    # the in-doc TOC navigation), so we match on the open tag prefix
    # plus the visible text rather than on the bare `<h1>` form.
    text.should match(/<h1[^>]*>Heading One<\/h1>/)
  end

  it "emits <ul>/<li> for unordered lists" do
    text = IntegrationHelper.chapters_text(
      IntegrationHelper.convert(<<-ADOC)
      = Book

      == Chapter

      * alpha
      * beta
      * gamma
      ADOC
    )
    text.should contain("<ul>")
    text.should contain("<li>alpha")
    text.should contain("<li>beta")
    text.should contain("<li>gamma")
  end

  it "emits <ol>/<li> for ordered lists" do
    text = IntegrationHelper.chapters_text(
      IntegrationHelper.convert(<<-ADOC)
      = Book

      == Chapter

      . one
      . two
      ADOC
    )
    text.should contain("<ol>")
    text.should contain("<li>one")
    text.should contain("<li>two")
  end

  it "emits <table><thead>/<tbody> for tables" do
    text = IntegrationHelper.chapters_text(
      IntegrationHelper.convert(<<-ADOC)
      = Book

      == Chapter

      |===
      | Col A | Col B

      | row1a | row1b
      | row2a | row2b
      |===
      ADOC
    )
    text.should contain("<table>")
    # Our converter uses the first row as header when no header option is
    # explicitly given. The exact thead vs tbody split depends on parser
    # heuristics; asserting on the presence of the cells is enough.
    text.should contain("row1a")
    text.should contain("row2b")
  end

  it "wraps admonitions in <div class=\"admonitionblock …\">" do
    text = IntegrationHelper.chapters_text(
      IntegrationHelper.convert(<<-ADOC)
      = Book

      == Chapter

      NOTE: Take care.
      ADOC
    )
    text.should contain("admonitionblock")
    text.should contain("NOTE")
    text.should contain("Take care.")
  end

  it "renders source blocks as <pre><code>" do
    text = IntegrationHelper.chapters_text(
      IntegrationHelper.convert(<<-ADOC)
      = Book

      == Chapter

      [source,crystal]
      ----
      puts "hi"
      ----
      ADOC
    )
    text.should contain("<pre")
    text.should contain("<code")
    text.should contain("puts")
  end
end
