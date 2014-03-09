class Observation < ActiveRecord::Base
  belongs_to :station

  #download the csv from obs the 2011-2013
  def self.download_obs(name)
    agent = Mechanize.new
    puts "sending obs from #{name} through mechanize"
    url =  "http://mesonet.agron.iastate.edu/cgi-bin/request/getData.py?station=#{name[1..3]}& \
      data=tmpf&data=dwpf&data=drct&data=sknt&data=p01i&year1=2010&year2=2013&month1=1&month2=12&day1=1& \
      day2=31&tz=GMT&format=comma&latlon=no".gsub!(/\s+/,"")
    agent.get(url).save "ASOS/#{name}.csv"
    puts name
  end

   def self.process_obs(name)
    require 'fileutils'
    fout = "ASOS/#{name}_fixed.csv"
    fin = "ASOS/#{name}.csv"
    File.open(fout,"w") do |out|
      File.foreach(fin) do |line|
        out.puts line unless line[0]=='#'
      end
    end
    FileUtils.mv(fout,fin)
    puts "done with #{name}"
  end
end
