require "crystal-asciidoctor"

module AsciidoctorEpub
  # Convertit un document AsciiDoc en EPUB3
  class Converter
    @builder : EpubBuilder

    def initialize
      @builder = EpubBuilder.new
    end

    # Convertit un document AsciiDoc et retourne les bytes EPUB
    def convert(doc : Asciidoctor::Document) : Bytes
      setup_metadata(doc)
      build_chapters(doc)
      EpubWriter.new(@builder).to_bytes
    end

    # Convertit un document AsciiDoc et écrit dans un fichier
    def convert_to_file(doc : Asciidoctor::Document, path : String)
      setup_metadata(doc)
      build_chapters(doc)
      EpubWriter.new(@builder).write(path)
    end

    private def setup_metadata(doc : Asciidoctor::Document)
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
    end

    private def build_chapters(doc : Asciidoctor::Document)
      # Si le document a des sections de niveau 1, chaque section = un chapitre
      sections = doc.blocks.select { |b| b.is_a?(Asciidoctor::Section) && b.as(Asciidoctor::Section).level == 1 }

      if sections.size > 0
        # Preamble (contenu avant la première section)
        preamble_blocks = doc.blocks.take_while { |b| !(b.is_a?(Asciidoctor::Section) && b.as(Asciidoctor::Section).level == 1) }
        if preamble_blocks.size > 0
          preamble_html = preamble_blocks.map { |b| convert_block(b) }.join("\n")
          add_chapter("preamble", doc.doctitle.to_s, "preamble.xhtml", preamble_html)
        end

        # Chapitres
        sections.each_with_index do |section, i|
          sect = section.as(Asciidoctor::Section)
          chapter_html = convert_section(sect)
          chapter_id = "chapter-#{i + 1}"
          filename = "#{chapter_id}.xhtml"
          add_chapter(chapter_id, sect.title.to_s, filename, chapter_html)
        end
      else
        # Document sans sections : un seul chapitre
        html = doc.blocks.map { |b| convert_block(b) }.join("\n")
        add_chapter("content", doc.doctitle.to_s, "content.xhtml", html)
      end
    end

    private def add_chapter(id : String, title : String, filename : String, body_html : String)
      xhtml = XhtmlBuilder.wrap(title, body_html, @builder.language, "styles/epub3.css")
      @builder.add_chapter(id, title, filename, xhtml)
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
        content = escape(block.source.to_s)
        %(  <pre><code>#{content}</code></pre>)
      when :admonition
        style = (block.attr("style") || block.attr("name") || "note").to_s.downcase
        content = apply_inline_subs(block)
        %(  <div class="admonitionblock #{style}">\n    <strong>#{style.upcase}</strong>\n    <p>#{content}</p>\n  </div>)
      when :quote
        content = apply_inline_subs(block)
        attribution = block.attr("attribution")
        html = %(  <blockquote>\n    <p>#{content}</p>\n)
        if attribution
          html += %(    <footer>— #{escape(attribution.to_s)}</footer>\n)
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

    private def convert_list(list : Asciidoctor::List) : String
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
      # Utilise le contenu avec substitutions appliquées
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
