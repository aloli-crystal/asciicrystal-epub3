#!/usr/bin/env crystal
require "./asciidoctor_epub"
require "option_parser"

input_file = ""
output_file = ""
sample_mode = false

OptionParser.parse do |parser|
  parser.banner = "Usage: asciicrystal-epub3 [options] fichier.adoc"
  parser.on("-o FILE", "--out-file FILE", "Output EPUB file (default: <input>.adoc.epub)") { |f| output_file = f }
  parser.on("--sample", "Generate reference document (reference.adoc + EPUB)") { sample_mode = true }
  parser.on("-h", "--help", "Show help") { puts parser; exit 0 }
  parser.on("-v", "--version", "Show version") { puts "asciicrystal-epub3 #{AsciicrystalEpub::VERSION}"; exit 0 }
  parser.unknown_args { |args| input_file = args.first? || "" }
end

if sample_mode
  # Le fichier de référence est dans asciicrystal (le shard cœur)
  sample_src = File.join(__DIR__, "..", "lib", "asciicrystal", "data", "samples", "reference.adoc")
  # Fallback : chercher dans le shard local
  unless File.exists?(sample_src)
    sample_src = File.join(__DIR__, "..", "data", "samples", "reference.adoc")
  end
  sample_dest = File.join(Dir.current, "reference.adoc")
  sample_epub = File.join(Dir.current, "reference.adoc.epub")
  File.write(sample_dest, File.read(sample_src))
  doc = Asciicrystal.load_file(sample_dest, {"safe" => "safe"})
  converter = AsciicrystalEpub::Converter.new
  converter.convert_to_file(doc, sample_epub)
  puts "Sample document generated: reference.adoc and reference.adoc.epub"
  exit 0
end

if input_file.empty?
  STDERR.puts "Error: no input file specified."
  STDERR.puts "Usage: asciicrystal-epub3 [options] file.adoc"
  exit 1
end

unless File.exists?(input_file)
  STDERR.puts "Error: file '#{input_file}' does not exist."
  exit 1
end

if output_file.empty?
  output_file = File.join(
    File.dirname(input_file),
    File.basename(input_file) + ".epub"
  )
end

doc = Asciicrystal.load_file(input_file, {"safe" => "safe"})
converter = AsciicrystalEpub::Converter.new
converter.convert_to_file(doc, output_file)

puts "EPUB generated: #{output_file}"
