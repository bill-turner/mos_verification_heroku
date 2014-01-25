class Station < ActiveRecord::Base

#### NOTE: both the obs and fcst functions have a parameter that should be some sort of
#### model-wide constant value that is used to determine how far back into the past we want
#### our forecast to go. Right now it is set to go to 'Today.day - 6.days' which will give
#### us a full week of forecasts to look at.
#--------------------------------------------------------------------------------------

  #this method will import data from the lib/stationlist.txt file into our database
  def self.addALLtheSTATIONS()
    File.foreach('lib/stationlist.txt') do |row|
      #first catch the lines with the state name
      if row.to_s[1]!=row.to_s[1].upcase then
        @state = row.strip
      #if the line is not the name of a state, then create a record in the database
      else
        longname = Station.import_helper(row[5..26])
        self.create(:name => row[0..3], :longname => longname, :state => @state, \
        :lat => row[33..37].to_f, :lon => -1*row[42..47].to_f)
      end
    end
  end

#------------------------------------------------------------------------------------------

  #helps format the :longname column in the stations table to clean up some of the messy data
  def self.import_helper(longname)
    if longname.include? 'ASOS' then longname.gsub!('ASOS','') end
    if longname.include? 'AWOS' then longname.gsub!('AWOS','') end
    if longname.include? 'AMOS' then longname.gsub!('AMOS','') end
    if longname.include? '()' then  longname.gsub!('()','') end
    longname = longname.rstrip
  end

#------------------------------------------------------------------------------------------

########################################################################################
################ FORECAST PROCESSING FUNCTIONS ########################################
########################################################################################

  #get forecast data and return it as an array of hashes
  #hourstring is something like '06:00', '12:00',  model is 'GFS' or 'NAM'
  def fetch_mos(model,hourstring)
    dates = 6.downto(0).map {|i| (Date.today - i.day).to_s}
    #dates = [(Date.today).to_s]
    hash_array = Array.new
    dates.each do |day|
      url = "http://mesonet.agron.iastate.edu/mos/csv.php?station=#{self.name}&  \
      runtime=#{day}%20#{hourstring}&model=#{model}".gsub(" ","")
      forecast = Station.parse_forecast(url)
      Station.make_mos_hash(hash_array,forecast)
    end
    return hash_array
  end

#------------------------------------------------------------------------------------------

  #take in a urlstring, parse page with nokogiri, delete first row(headers), return the array of arrays
  def self.parse_forecast(url)
    require 'open-uri'
    data = Nokogiri.HTML(open(url)).text.split("\n").to_a.map {|row| row.split(',')}
    data.delete_at 0
    return data
  end

#-------------------------------------------------------------------------------------------

  #loop through array of arrays ('data') made in the 'parse_forecast', create an array of hashes
  def self.make_mos_hash(hash, data)
    data.each {|row| hash << {:model => row[1], :runtime => row[2], :ftime => row[3], :tmp => row[5], \
    :dpt => row[6], :cld => row[7], :wdr => row[8], :wsp => row[9]}}
    return hash
  end

#--------------------------------------------------------------------------------------------

  #accept the hash array full of forecast data, pull out desired variable, format for highcharts grapher
  def self.prep_mos_array(hash, wxvar)
    view_data = hash.map do |row|
      [row[:ftime].to_datetime.to_i*1000, row[wxvar.to_sym].to_f]
    end
  end

#---------------------------------------------------------------------------------------------

  #call fetch_mos function and blend the data together. if we look at a series of forecast
  #issued each day, starting at Today-3.days, Today-2.days, Today-1.day, and Today ... There
  #will be overlapping data where the model from yesterday has forecasts that overlap with the
  #forecast from today. This causes our series to lose it's one-to-one relationship and the graph
  #is ugly. This function will find all 'forecast_times' (:ftime) that overlap, and then
  #average out the data. Also we will destroy some of the duplicate forecast times so that we have
  #a unique datetime stamp for each datapoint.
  def blend_forecast(model,timestring,field)
    #call self.fetch_mos to build array of hashes, than sort that by :ftime
    sorted_array = self.fetch_mos(model,timestring).sort_by {|hash| hash[:ftime]}
    final_array = self.process_sorted_mos_array(sorted_array,field)
  end

#-----------------------------------------------------------------------------------------------

  #loop through array, find duplicates, average values, delete extraneous records
  #loop has to run twice to remove all duplicates!
  def process_sorted_mos_array(s,field)
    f = field.to_sym
    2.times do |x|
      1.upto(s.length-1) do |i|
        unless s[i].nil?
          if (s[i][:ftime]==s[i-1][:ftime])
            s[i-1][f] = (((s[i][f]).to_f + (s[i-1][f]).to_f)/2).to_s
            s.delete_at(i)
          end
        end
      end
    end
    return s
  end


  def prep_mos_windrose(model,timestring)
    windspeed_hash = self.blend_forecast(model,timestring,"wsp")
    winddir_hash = self.blend_forecast(model,timestring,"Wdr")
    array_of_winddirs = Station.sort_wind_dir(winddir_hash)
    array_of_windspeeds = Station.sort_wind_spd(windspeed_hash)
  end

  #input the hash_array with the forecast data, pull out the wdr data, sort it into bins [N,NNE,NE,ENE,E...NNW]
  def self.sort_wind_dir(hash)
    output_array = Array.new
    n = hash.map {|row| if row[:wdr].to_f.between?(0,11.25)&&row[:wdr].to_f.between?(348.75,360) then row[:wdr] end}
    nne = (hash.map {|row| if row[:wdr].to_f.between?(11.25,33.75) then row[:wdr] end})
    ne = (hash.map {|row| if row[:wdr].to_f.between?(33.75,56.25) then row[:wdr] end})
    ene = (hash.map {|row| if row[:wdr].to_f.between?(56.25,78.75) then row[:wdr] end})
    e = (hash.map {|row| if row[:wdr].to_f.between?(78.75,101.25) then row[:wdr] end})
    ese = (hash.map {|row| if row[:wdr].to_f.between?(101.25,123.75) then row[:wdr] end})
    se = (hash.map {|row| if row[:wdr].to_f.between?(123.75,146.25) then row[:wdr] end})
    sse = (hash.map {|row| if row[:wdr].to_f.between?(146.25,168.75) then row[:wdr] end})
    s = (hash.map {|row| if row[:wdr].to_f.between?(168.75,191.25) then row[:wdr] end})
    ssw = (hash.map {|row| if row[:wdr].to_f.between?(191.25,213.75) then row[:wdr] end})
    sw = (hash.map {|row| if row[:wdr].to_f.between?(213.75,236.25) then row[:wdr] end})
    wsw = (hash.map {|row| if row[:wdr].to_f.between?(236.25,258.75) then row[:wdr] end})
    w = (hash.map {|row| if row[:wdr].to_f.between?(258.75,281.25) then row[:wdr] end})
    wnw = (hash.map {|row| if row[:wdr].to_f.between?(281.25,303.75) then row[:wdr] end})
    nw = (hash.map {|row| if row[:wdr].to_f.between?(303.75,326.25) then row[:wdr] end})
    nnw = (hash.map {|row| if row[:wdr].to_f.between?(326.25,348.75) then row[:wdr] end})
    output_array.push(n,nne,ne,ene,e,ese,se,sse,s,ssw,sw,wsw,w,wnw,nw,nnw)
    output_array.map! {|row| row.compact}
  end


  def self.sort_wind_spd(wsp_hash)

  end
###########################################################################################
################### END FORECAST PROCESSING FUNCTIONS #######################################
###########################################################################################

#----------------------------------------------------------------------------------------------

#############################################################################################
################### OBSERVATION PROCESSING FUNCTIONS ##########################################
#############################################################################################

  def fetch_past_obs(field)
    begin_day, begin_month, begin_year, end_day, end_month, end_year = Station.get_date_info
    url =  "http://mesonet.agron.iastate.edu/cgi-bin/request/getData.py?station=#{self.name[1..3]}& \
    data=tmpf&data=dwpf&data=relh&data=drct&data=sknt&data=p01i&data=mslp&&data=skyc1& \
    year1=#{begin_year}&year2=#{end_year}&month1=#{begin_month}&month2=#{end_month}&day1=#{begin_day}&\
    day2=#{end_day}&tz=GMT&format=comma&latlon=no".gsub!(/\s+/,"")
    obs = Station.parse_obs(url)
    ob_hash = Station.make_obs_hash(obs)
  end

  def self.get_date_info
    begin_date = Date.today - 6.days
    begin_year = begin_date.year.to_s
    begin_month = begin_date.month.to_s
    begin_day = begin_date.day.to_s
    end_date = Date.today
    end_year = end_date.year.to_s
    end_month = end_date.month.to_s
    end_day = end_date.day.to_s
    return begin_day, begin_month, begin_year, end_day, end_month, end_year
  end

  def self.parse_obs(url)
    require 'open-uri'
    data = Nokogiri.HTML(open(url)).text.split("\n").to_a.map {|row| row.split(',')}
    4.times {|i| data.delete_at(0)}
    return data
  end

  def self.make_obs_hash(data)
    hash = []
    data.each {|row| hash << {:vtime => row[1], :tmp => row[2], :dpt => row[3],:wdr => row[5], :wsp => row[6] }}
    return hash
  end

  def self.prep_obs_array(obs,field)
    view_data = obs.map do |row|
      [row[:vtime].to_datetime.to_i*1000, row[field.to_sym].to_f]
    end
  end

end

