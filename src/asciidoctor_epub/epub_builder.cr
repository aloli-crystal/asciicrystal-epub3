require "html"
require "uuid"

module AsciidoctorEpub
  # Genere les fichiers de structure EPUB3 : content.opf, toc.ncx, nav.xhtml
  class EpubBuilder
    # A TOC entry for sub-sections within a chapter.
    # `id` is the XHTML element id used as the in-document anchor; the
    # nav.xhtml and toc.ncx render `href="<file>#<id>"` so that clicking
    # a sub-section in the table of contents jumps to the matching
    # heading inside the chapter, not just to the top of the file.
    record TocEntry, title : String, id : String,
      children : Array(TocEntry) = [] of TocEntry

    record Chapter, id : String, title : String, filename : String, content : String,
      children : Array(TocEntry) = [] of TocEntry
    record Resource, id : String, filename : String, media_type : String

    property title : String = "Untitled"
    property authors : Array(String) = [] of String
    property language : String = "en"
    property identifier : String = ""
    property description : String = ""
    property publisher : String = ""
    property date : String = ""
    property cover_image : String? = nil

    getter chapters : Array(Chapter) = [] of Chapter
    getter resources : Array(Resource) = [] of Resource

    def initialize
      @identifier = "urn:uuid:#{UUID.random}"
    end

    def add_chapter(id : String, title : String, filename : String, content : String,
                    children : Array(TocEntry) = [] of TocEntry)
      @chapters << Chapter.new(id: id, title: title, filename: filename, content: content, children: children)
    end

    def add_resource(id : String, filename : String, media_type : String)
      @resources << Resource.new(id: id, filename: filename, media_type: media_type)
    end

    # Genere le fichier META-INF/container.xml
    def container_xml : String
      <<-XML
      <?xml version="1.0" encoding="UTF-8"?>
      <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles>
      </container>
      XML
    end

    # Genere le fichier OEBPS/content.opf (manifeste EPUB3)
    def content_opf : String
      modified = Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ")

      String.build do |io|
        io << %(<?xml version="1.0" encoding="UTF-8"?>\n)
        io << %(<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">\n)

        # Metadata
        io << %(  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n)
        io << %(    <dc:identifier id="pub-id">#{escape(identifier)}</dc:identifier>\n)
        io << %(    <dc:title>#{escape(title)}</dc:title>\n)
        io << %(    <dc:language>#{escape(language)}</dc:language>\n)
        authors.each { |a| io << %(    <dc:creator>#{escape(a)}</dc:creator>\n) }
        io << %(    <dc:description>#{escape(description)}</dc:description>\n) unless description.empty?
        io << %(    <dc:publisher>#{escape(publisher)}</dc:publisher>\n) unless publisher.empty?
        io << %(    <dc:date>#{escape(date)}</dc:date>\n) unless date.empty?
        io << %(    <meta property="dcterms:modified">#{modified}</meta>\n)
        io << %(  </metadata>\n)

        # Manifest
        io << %(  <manifest>\n)
        io << %(    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\n)
        io << %(    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>\n)
        io << %(    <item id="stylesheet" href="styles/epub3.css" media-type="text/css"/>\n)

        if ci = cover_image
          ext = File.extname(ci).lstrip('.')
          media = case ext
                  when "jpg", "jpeg" then "image/jpeg"
                  when "png"         then "image/png"
                  when "gif"         then "image/gif"
                  when "svg"         then "image/svg+xml"
                  else                    "image/jpeg"
                  end
          io << %(    <item id="cover-image" href="#{escape(ci)}" media-type="#{media}" properties="cover-image"/>\n)
        end

        chapters.each do |ch|
          io << %(    <item id="#{escape(ch.id)}" href="#{escape(ch.filename)}" media-type="application/xhtml+xml"/>\n)
        end

        resources.each do |r|
          io << %(    <item id="#{escape(r.id)}" href="#{escape(r.filename)}" media-type="#{escape(r.media_type)}"/>\n)
        end

        io << %(  </manifest>\n)

        # Spine
        io << %(  <spine toc="ncx">\n)
        chapters.each do |ch|
          io << %(    <itemref idref="#{escape(ch.id)}"/>\n)
        end
        io << %(  </spine>\n)

        io << %(</package>\n)
      end
    end

    # Compute the maximum TOC depth across all chapters
    private def max_toc_depth : Int32
      max = 1
      chapters.each do |ch|
        depth = 1 + max_depth(ch.children)
        max = depth if depth > max
      end
      max
    end

    private def max_depth(entries : Array(TocEntry)) : Int32
      return 0 if entries.empty?
      entries.map { |e| 1 + max_depth(e.children) }.max
    end

    # Genere le fichier OEBPS/toc.ncx (navigation EPUB2 compat)
    def toc_ncx : String
      play_order = [0] # mutable counter wrapped in array

      String.build do |io|
        io << %(<?xml version="1.0" encoding="UTF-8"?>\n)
        io << %(<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n)
        io << %(  <head>\n)
        io << %(    <meta name="dtb:uid" content="#{escape(identifier)}"/>\n)
        io << %(    <meta name="dtb:depth" content="#{max_toc_depth}"/>\n)
        io << %(    <meta name="dtb:totalPageCount" content="0"/>\n)
        io << %(    <meta name="dtb:maxPageNumber" content="0"/>\n)
        io << %(  </head>\n)
        io << %(  <docTitle><text>#{escape(title)}</text></docTitle>\n)
        io << %(  <navMap>\n)

        chapters.each do |ch|
          play_order[0] += 1
          order = play_order[0]
          io << %(    <navPoint id="navpoint-#{order}" playOrder="#{order}">\n)
          io << %(      <navLabel><text>#{escape(ch.title)}</text></navLabel>\n)
          io << %(      <content src="#{escape(ch.filename)}"/>\n)

          # Nested sub-sections
          render_ncx_children(io, ch.children, ch.filename, play_order, 6)

          io << %(    </navPoint>\n)
        end

        io << %(  </navMap>\n)
        io << %(</ncx>\n)
      end
    end

    private def render_ncx_children(io : IO, entries : Array(TocEntry), parent_filename : String,
                                    play_order : Array(Int32), indent : Int32)
      entries.each do |entry|
        play_order[0] += 1
        order = play_order[0]
        pad = " " * indent
        # Point to the parent file with a fragment anchor so the EPUB
        # reader scrolls to the matching heading, not just to the top
        # of the chapter.
        href = "#{parent_filename}##{entry.id}"
        io << %(#{pad}<navPoint id="navpoint-#{order}" playOrder="#{order}">\n)
        io << %(#{pad}  <navLabel><text>#{escape(entry.title)}</text></navLabel>\n)
        io << %(#{pad}  <content src="#{escape(href)}"/>\n)

        render_ncx_children(io, entry.children, parent_filename, play_order, indent + 4) unless entry.children.empty?

        io << %(#{pad}</navPoint>\n)
      end
    end

    # Genere le fichier OEBPS/nav.xhtml (navigation EPUB3)
    def nav_xhtml : String
      String.build do |io|
        io << %(<?xml version="1.0" encoding="UTF-8"?>\n)
        io << %(<!DOCTYPE html>\n)
        io << %(<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="#{escape(language)}">\n)
        io << %(<head>\n)
        io << %(  <meta charset="UTF-8"/>\n)
        io << %(  <title>#{escape(title)}</title>\n)
        io << %(  <link rel="stylesheet" type="text/css" href="styles/epub3.css"/>\n)
        io << %(</head>\n)
        io << %(<body>\n)
        io << %(  <nav epub:type="toc" id="toc">\n)
        io << %(    <h1>Table of Contents</h1>\n)
        io << %(    <ol>\n)

        chapters.each do |ch|
          if ch.children.empty?
            io << %(      <li><a href="#{escape(ch.filename)}">#{escape(ch.title)}</a></li>\n)
          else
            io << %(      <li>\n)
            io << %(        <a href="#{escape(ch.filename)}">#{escape(ch.title)}</a>\n)
            render_nav_children(io, ch.children, ch.filename, 8)
            io << %(      </li>\n)
          end
        end

        io << %(    </ol>\n)
        io << %(  </nav>\n)
        io << %(</body>\n)
        io << %(</html>\n)
      end
    end

    private def render_nav_children(io : IO, entries : Array(TocEntry), parent_filename : String, indent : Int32)
      pad = " " * indent
      io << %(#{pad}<ol>\n)
      entries.each do |entry|
        # Same logic as the NCX path: chain the entry's anchor id to
        # the parent filename so the link jumps inside the chapter.
        href = "#{parent_filename}##{entry.id}"
        if entry.children.empty?
          io << %(#{pad}  <li><a href="#{escape(href)}">#{escape(entry.title)}</a></li>\n)
        else
          io << %(#{pad}  <li>\n)
          io << %(#{pad}    <a href="#{escape(href)}">#{escape(entry.title)}</a>\n)
          render_nav_children(io, entry.children, parent_filename, indent + 4)
          io << %(#{pad}  </li>\n)
        end
      end
      io << %(#{pad}</ol>\n)
    end

    private def escape(text : String) : String
      HTML.escape(text)
    end
  end
end
