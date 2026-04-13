require "crystal-asciidoctor"

module AsciidoctorEpub
  # Convertit un document AsciiDoc en EPUB3
  class Converter
    @builder : EpubBuilder
    @image_files : Hash(String, String) = {} of String => String # epub_path => local_path
    @base_dir : String = "."
    @doc : Asciidoctor::Document? = nil

    def initialize
      @builder = EpubBuilder.new
    end

    # Convertit un document AsciiDoc et retourne les bytes EPUB
    def convert(doc : Asciidoctor::Document) : Bytes
      setup_metadata(doc)
      setup_cover(doc)
      build_chapters(doc)
      EpubWriter.new(@builder, @image_files).to_bytes
    end

    # Convertit un document AsciiDoc et ecrit dans un fichier
    def convert_to_file(doc : Asciidoctor::Document, path : String)
      setup_metadata(doc)
      setup_cover(doc)
      build_chapters(doc)
      EpubWriter.new(@builder, @image_files).write(path)
    end

    private def setup_metadata(doc : Asciidoctor::Document)
      @base_dir = doc.base_dir
      @builder.title = doc.doctitle.to_s
      @builder.language = doc.attr("lang").try(&.to_s) || "en"

      if author = doc.attr("author")
        @builder.authors = [author.to_s]
      end

      if revdate = doc.attr("revdate")
        @builder.date = revdate.to_s
      end

      if description = doc.attr("description")
        @builder.description = description.to_s
      end

      if publisher = doc.attr("publisher")
        @builder.publisher = publisher.to_s
      end

      @doc = doc
    end

    private def setup_cover(doc : Asciidoctor::Document)
      cover_attr = doc.attr("front-cover-image")
      return unless cover_attr

      cover_target = cover_attr.to_s
      # Strip image: macro wrapper if present (e.g. "image:cover.jpg[]")
      if cover_target =~ /^image::?(.+?)\[.*\]$/
        cover_target = $1
      end

      imagesdir = doc.attr("imagesdir").try(&.to_s) || ""
      local_path = resolve_image_path(cover_target, imagesdir)

      epub_path = "images/#{cover_target}"
      @builder.cover_image = epub_path
      @image_files[epub_path] = local_path

      # Generate cover page XHTML and add as first chapter
      cover_xhtml = XhtmlBuilder.cover_page(@builder.title, epub_path, @builder.language)
      @builder.add_chapter("cover", "Cover", "cover.xhtml", cover_xhtml)
    end

    private def build_chapters(doc : Asciidoctor::Document)
      # Si le document a des sections de niveau 1, chaque section = un chapitre
      sections = doc.blocks.select { |b| b.is_a?(Asciidoctor::Section) && b.as(Asciidoctor::Section).level == 1 }

      if sections.size > 0
        # Preamble (contenu avant la premiere section)
        preamble_blocks = doc.blocks.take_while { |b| !(b.is_a?(Asciidoctor::Section) && b.as(Asciidoctor::Section).level == 1) }
        if preamble_blocks.size > 0
          preamble_html = preamble_blocks.map { |b| convert_block(b) }.join("\n")
          add_chapter("preamble", doc.doctitle.to_s, "preamble.xhtml", preamble_html)
        end

        # Chapitres
        sections.each_with_index do |section, i|
          sect = section.as(Asciidoctor::Section)
          chapter_html = convert_section(sect)

          # Collect sub-sections for hierarchical TOC
          children = collect_subsections(sect)

          # Append footnotes at the end of each chapter (collected during inline subs)
          if (d = @doc) && d.footnotes?
            chapter_html += render_footnotes(d.footnotes)
          end

          chapter_id = "chapter-#{i + 1}"
          filename = "#{chapter_id}.xhtml"
          add_chapter(chapter_id, sect.title.to_s, filename, chapter_html, children)
        end
      else
        # Document sans sections : un seul chapitre
        html = doc.blocks.map { |b| convert_block(b) }.join("\n")

        if (d = @doc) && d.footnotes?
          html += render_footnotes(d.footnotes)
        end

        add_chapter("content", doc.doctitle.to_s, "content.xhtml", html)
      end
    end

    private def collect_subsections(section : Asciidoctor::Section) : Array(EpubBuilder::TocEntry)
      entries = [] of EpubBuilder::TocEntry
      section.blocks.each do |block|
        if block.is_a?(Asciidoctor::Section)
          sub = block.as(Asciidoctor::Section)
          children = collect_subsections(sub)
          entries << EpubBuilder::TocEntry.new(sub.title.to_s, children)
        end
      end
      entries
    end

    private def add_chapter(id : String, title : String, filename : String, body_html : String,
                            children : Array(EpubBuilder::TocEntry) = [] of EpubBuilder::TocEntry)
      xhtml = XhtmlBuilder.wrap(title, body_html, @builder.language, "styles/epub3.css")
      @builder.add_chapter(id, title, filename, xhtml, children)
    end

    private def render_footnotes(footnotes : Array(Asciidoctor::Document::Footnote)) : String
      String.build do |io|
        io << %(\n  <hr class="footnotes-separator"/>\n)
        io << %(  <div class="footnotes">\n)
        io << %(    <ol>\n)
        footnotes.each do |fn|
          fn_id = fn.id || fn.index.to_s
          io << %(      <li id="fn-#{HTML.escape(fn_id)}">\n)
          io << %(        <p>#{fn.text || ""} <a href="#fnref-#{HTML.escape(fn_id)}">&#8617;</a></p>\n)
          io << %(      </li>\n)
        end
        io << %(    </ol>\n)
        io << %(  </div>\n)
      end
    end

    private def convert_section(section : Asciidoctor::Section) : String
      String.build do |io|
        level = section.level
        io << %(  <section>\n)
        io << %(    <h#{level}>#{escape(section.title.to_s)}</h#{level}>\n)

        section.blocks.each do |block|
          io << convert_block(block)
          io << "\n"
        end

        io << %(  </section>\n)
      end
    end

    private def convert_block(block : Asciidoctor::AbstractBlock) : String
      case block
      when Asciidoctor::Section
        convert_section(block)
      when Asciidoctor::Block
        convert_content_block(block)
      when Asciidoctor::List
        convert_list(block)
      when Asciidoctor::Table
        convert_table(block)
      else
        ""
      end
    end

    private def convert_content_block(block : Asciidoctor::Block) : String
      case block.context
      when :paragraph
        content = apply_inline_subs(block)
        %(  <p>#{content}</p>)
      when :listing, :literal
        source = block.source.to_s
        lang = block.attr("language")
        if lang && (lexer = Rouge::RegexLexer.find(lang))
          tokens = lexer.lex(source)
          highlighted = Rouge::Formatters::HTML.new.format(tokens)
          %(  <pre class="highlight"><code data-lang="#{escape(lang)}">#{highlighted}</code></pre>)
        else
          %(  <pre><code>#{escape(source)}</code></pre>)
        end
      when :admonition
        style = (block.attr("style") || block.attr("name") || "note").to_s.downcase
        content = apply_inline_subs(block)
        %(  <div class="admonitionblock #{style}">\n    <strong>#{style.upcase}</strong>\n    <p>#{content}</p>\n  </div>)
      when :quote
        content = apply_inline_subs(block)
        attribution = block.attr("attribution")
        html = %(  <blockquote>\n    <p>#{content}</p>\n)
        if attribution
          html += %(    <footer>-- #{escape(attribution.to_s)}</footer>\n)
        end
        html += %(  </blockquote>)
        html
      when :verse
        content = escape(block.source.to_s)
        %(  <pre class="verse">#{content}</pre>)
      when :example
        content = block.blocks.map { |b| convert_block(b) }.join("\n")
        %(  <div class="example">\n#{content}\n  </div>)
      when :sidebar
        content = block.blocks.map { |b| convert_block(b) }.join("\n")
        %(  <aside>\n#{content}\n  </aside>)
      when :image
        target = block.attr("target").to_s
        alt = block.attr("alt").try(&.to_s) || ""

        # Embed image in EPUB ZIP
        embed_image(target, block)

        %(  <figure>\n    <img src="images/#{escape(target)}" alt="#{escape(alt)}"/>\n  </figure>)
      when :thematic_break
        %(  <hr/>)
      when :pass
        block.source.to_s
      when :open
        block.blocks.map { |b| convert_block(b) }.join("\n")
      else
        content = apply_inline_subs(block)
        %(  <div class="#{block.context}">#{content}</div>) unless content.empty?
      end || ""
    end

    private def embed_image(target : String, block : Asciidoctor::AbstractBlock)
      imagesdir = block.document.attr("imagesdir").try(&.to_s) || ""
      local_path = resolve_image_path(target, imagesdir)

      epub_path = "images/#{target}"
      return if @image_files.has_key?(epub_path) # Already tracked

      @image_files[epub_path] = local_path

      # Determine media type
      ext = File.extname(target).lstrip('.').downcase
      media_type = case ext
                   when "jpg", "jpeg" then "image/jpeg"
                   when "png"         then "image/png"
                   when "gif"         then "image/gif"
                   when "svg"         then "image/svg+xml"
                   when "webp"        then "image/webp"
                   else                    "application/octet-stream"
                   end

      # Add as resource to the builder for the OPF manifest
      resource_id = "img-#{target.gsub(/[^a-zA-Z0-9_-]/, "_")}"
      @builder.add_resource(resource_id, epub_path, media_type)
    end

    private def resolve_image_path(target : String, imagesdir : String) : String
      if imagesdir.empty?
        File.join(@base_dir, target)
      else
        File.join(@base_dir, imagesdir, target)
      end
    end

    private def convert_list(list : Asciidoctor::List) : String
      case list.context
      when :dlist
        convert_dlist(list)
      else
        tag = list.context == :olist ? "ol" : "ul"
        String.build do |io|
          io << %(  <#{tag}>\n)
          list.items.each do |item|
            if item.is_a?(Asciidoctor::ListItem)
              text = apply_inline_subs_from_text(item.text.to_s)
              io << %(    <li>#{text})
              if item.blocks.size > 0
                io << "\n"
                item.blocks.each { |b| io << convert_block(b) << "\n" }
                io << %(    )
              end
              io << %(</li>\n)
            end
          end
          io << %(  </#{tag}>)
        end
      end
    end

    private def convert_dlist(list : Asciidoctor::List) : String
      String.build do |io|
        io << %(  <dl>\n)
        items = list.items
        i = 0
        while i < items.size
          item = items[i]
          if item.is_a?(Asciidoctor::ListItem)
            marker = item.marker
            if marker != "desc"
              # Term (dt)
              io << %(    <dt>#{item.text || ""}</dt>\n)
              # Check if next item is a description (dd)
              if i + 1 < items.size && items[i + 1].is_a?(Asciidoctor::ListItem) && items[i + 1].as(Asciidoctor::ListItem).marker == "desc"
                desc_item = items[i + 1].as(Asciidoctor::ListItem)
                io << %(    <dd>)
                desc_text = desc_item.text || ""
                if desc_item.blocks.size > 0
                  io << %(<p>#{desc_text}</p>) unless desc_text.to_s.empty?
                  desc_item.blocks.each { |b| io << convert_block(b) }
                else
                  io << desc_text.to_s
                end
                io << %(</dd>\n)
                i += 2
                next
              end
            end
          end
          i += 1
        end
        io << %(  </dl>)
      end
    end

    private def convert_table(table : Asciidoctor::Table) : String
      String.build do |io|
        io << %(  <table>\n)

        # Header
        if table.rows.head.size > 0
          io << %(    <thead>\n)
          table.rows.head.each do |row|
            io << %(      <tr>\n)
            row.each do |cell|
              io << %(        <th>#{escape(cell.text.to_s)}</th>\n)
            end
            io << %(      </tr>\n)
          end
          io << %(    </thead>\n)
        end

        # Body
        if table.rows.body.size > 0
          io << %(    <tbody>\n)
          table.rows.body.each do |row|
            io << %(      <tr>\n)
            row.each do |cell|
              io << %(        <td>#{escape(cell.text.to_s)}</td>\n)
            end
            io << %(      </tr>\n)
          end
          io << %(    </tbody>\n)
        end

        io << %(  </table>)
      end
    end

    private def apply_inline_subs(block : Asciidoctor::Block) : String
      # Utilise le contenu avec substitutions appliquees
      if (content = block.content)
        content.to_s
      else
        escape(block.source.to_s)
      end
    end

    private def apply_inline_subs_from_text(text : String) : String
      # Substitutions inline basiques
      text
    end

    private def escape(text : String) : String
      HTML.escape(text)
    end
  end
end
