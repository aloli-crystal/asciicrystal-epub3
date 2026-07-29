module AsciicrystalEpub
  # Génère des fichiers XHTML5 valides pour les chapitres EPUB
  class XhtmlBuilder
    def self.wrap(title : String, body : String, language : String = "en", stylesheet : String = "../styles/epub3.css") : String
      String.build do |io|
        io << %(<?xml version="1.0" encoding="UTF-8"?>\n)
        io << %(<!DOCTYPE html>\n)
        io << %(<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="#{HTML.escape(language)}">\n)
        io << %(<head>\n)
        io << %(  <meta charset="UTF-8"/>\n)
        io << %(  <title>#{HTML.escape(title)}</title>\n)
        io << %(  <link rel="stylesheet" type="text/css" href="#{stylesheet}"/>\n)
        io << %(</head>\n)
        io << %(<body>\n)
        io << body
        io << %(\n</body>\n)
        io << %(</html>\n)
      end
    end

    # Génère une page de couverture
    def self.cover_page(title : String, image_path : String, language : String = "en") : String
      body = String.build do |io|
        io << %(  <section epub:type="cover">\n)
        io << %(    <img src="#{HTML.escape(image_path)}" alt="#{HTML.escape(title)}"/>\n)
        io << %(  </section>\n)
      end
      wrap(title, body, language)
    end

    # Génère une page de titre
    def self.title_page(title : String, authors : Array(String), language : String = "en") : String
      body = String.build do |io|
        io << %(  <section epub:type="titlepage">\n)
        io << %(    <h1>#{HTML.escape(title)}</h1>\n)
        authors.each do |author|
          io << %(    <p class="author">#{HTML.escape(author)}</p>\n)
        end
        io << %(  </section>\n)
      end
      wrap(title, body, language)
    end
  end
end
