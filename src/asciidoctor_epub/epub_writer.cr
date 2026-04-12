require "compress/zip"

module AsciidoctorEpub
  # Assemble un fichier EPUB (ZIP) à partir d'un EpubBuilder
  class EpubWriter
    def initialize(@builder : EpubBuilder)
    end

    # Écrit l'EPUB dans un fichier
    def write(path : String)
      File.open(path, "w") do |file|
        write_to(file)
      end
    end

    # Écrit l'EPUB dans un IO (pour usage en mémoire / serveur web)
    def write_to(io : IO)
      Compress::Zip::Writer.open(io) do |zip|
        # Le fichier mimetype DOIT être le premier et non compressé
        zip.add("mimetype", &.print("application/epub+zip"))

        # META-INF
        zip.add("META-INF/container.xml", &.print(@builder.container_xml))

        # OEBPS structure
        zip.add("OEBPS/content.opf", &.print(@builder.content_opf))
        zip.add("OEBPS/toc.ncx", &.print(@builder.toc_ncx))
        zip.add("OEBPS/nav.xhtml", &.print(@builder.nav_xhtml))

        # Stylesheet
        zip.add("OEBPS/styles/epub3.css", &.print(default_stylesheet))

        # Chapters
        @builder.chapters.each do |chapter|
          zip.add("OEBPS/#{chapter.filename}", &.print(chapter.content))
        end
      end
    end

    # Écrit l'EPUB en mémoire et retourne les bytes
    def to_bytes : Bytes
      io = IO::Memory.new
      write_to(io)
      io.to_slice
    end

    private def default_stylesheet : String
      css_path = File.join(__DIR__, "..", "..", "data", "styles", "epub3.css")
      if File.exists?(css_path)
        File.read(css_path)
      else
        DEFAULT_CSS
      end
    end

    DEFAULT_CSS = <<-CSS
    /* crystal-asciidoctor-epub default stylesheet */
    body {
      font-family: Georgia, "Times New Roman", serif;
      line-height: 1.6;
      margin: 1em;
      color: #333;
    }
    h1, h2, h3, h4, h5, h6 {
      font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
      margin-top: 1.5em;
      margin-bottom: 0.5em;
      color: #111;
    }
    h1 { font-size: 2em; }
    h2 { font-size: 1.5em; }
    h3 { font-size: 1.25em; }
    code, pre {
      font-family: "Courier New", Courier, monospace;
      font-size: 0.9em;
    }
    pre {
      background: #f5f5f5;
      padding: 1em;
      overflow-x: auto;
      border: 1px solid #ddd;
    }
    code {
      background: #f0f0f0;
      padding: 0.15em 0.3em;
    }
    pre code {
      background: none;
      padding: 0;
    }
    blockquote {
      margin: 1em 0;
      padding: 0.5em 1em;
      border-left: 3px solid #ccc;
      color: #555;
    }
    table {
      border-collapse: collapse;
      width: 100%;
      margin: 1em 0;
    }
    th, td {
      border: 1px solid #ddd;
      padding: 0.5em;
      text-align: left;
    }
    th {
      background: #f0f0f0;
      font-weight: bold;
    }
    img {
      max-width: 100%;
      height: auto;
    }
    .admonitionblock {
      margin: 1em 0;
      padding: 0.75em 1em;
      border-left: 4px solid #666;
      background: #fafafa;
    }
    .admonitionblock.note { border-color: #4a90d9; }
    .admonitionblock.tip { border-color: #4caf50; }
    .admonitionblock.warning { border-color: #ff9800; }
    .admonitionblock.caution { border-color: #f44336; }
    .admonitionblock.important { border-color: #e91e63; }
    a { color: #2156a5; text-decoration: none; }
    .author { font-style: italic; color: #666; }
    CSS
  end
end
