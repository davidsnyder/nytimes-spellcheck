require 'rubygems'
require 'nokogiri'
require 'restclient'
require 'ffi/aspell'
require 'fileutils'

ARCHIVE_YEARS = [1996]
ARCHIVE_MONTHS = ["01"] #%w(01 02 03 04 05 06 07 08 09 10 11 12)
ARCHIVE_PARTS = [0] #0..3
PUNCTUATION = /[.,?;:!()\[\]]/
SKIP_WORDS = []

def get_archive_url(year, month, part)
  return "https://spiderbites.nytimes.com/#{year}/articles_#{year}_#{month}_0000#{part}.html"
end

def fetch_all_headlines(year)
  headline_urls = []  
      ARCHIVE_MONTHS.each do |month|
        ARCHIVE_PARTS.each do |part|
          url= get_archive_url(year, month, part)
          $stderr.puts "Fetching #{url}"
          begin 
            page = Nokogiri::HTML(RestClient.get(url))
          rescue StandardError => e
            $stderr.puts(e)
          end
          page.css("ul#headlines li a").each do |link|
            if link.attributes.has_key?("href")
              headline_urls << link.attributes["href"].value
            end
          end
        end
      end
  headline_urls
end

ARCHIVE_YEARS.each do |year|
  headline_urls = fetch_all_headlines(year)
  headline_urls[0..20].each do |url|
    page = Nokogiri::HTML(RestClient.get(url))
    story_content = page.css("p.story-content").map{|paragraph| paragraph.children[0].to_s }
    tokens = {}
    story = story_content.each_with_index do |sent, index|
      stripped = sent.split(" ").map do |w|
        if /\w+-\w+/ =~ w
          toks = w.split("-")
        else
          toks = [w]
        end
        toks.map{|t| t.delete_prefix('"').delete_prefix("'").delete_suffix("'").delete_suffix('"').gsub(PUNCTUATION,'') }
      end
      stripped.flatten.each do |w|
        tokens[w] = index
      end
    end
    url = url.delete_prefix('http://www.nytimes.com/').delete_suffix('.html')
    y,m,s,c,headline = url.split("/")
    path = [y,m,s].join("/")
    FileUtils.mkdir_p path
    path = [path,headline].join("/")
    typos = []        
    tokens.keys.each do |word|
      next if SKIP_WORDS.include?(word)
      next if /--/ =~ word #dashes
      next if /\d+/ =~ word #numbers, years
      next if /^[A-Z]/ =~ word #proper nouns
      next if /&amp/ =~ word #ampersand
      FFI::Aspell::Speller.open('en_US') do |speller|      
        unless speller.correct?(word)
          typos << [word,story_content[tokens[word]]]
        end
      end
    end
    if typos.length > 0 
      $stderr.puts("Writing #{path}")
      File.open(path, 'w') do |file|
        typos.each do |t|
          next if SKIP_WORDS.include?(t[0])
          print t
          print "\nWrite typo? [y/n/s] "
          answer = gets.chomp
          if answer == "y"
            file.write(t.join("\t") + "\n")
          elsif answer == "s"
            SKIP_WORDS << t[0]
          end
        end
      end
      FileUtils.rm(path) if File.size(path) == 0
    end
  end
end

  
