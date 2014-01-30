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
################ FORECAST TIME SERIES FUNCTIONS ########################################
########################################################################################

  #get forecast data and return it as an array of hashes
  #hourstring is something like '06:00', '12:00',  model is 'GFS' or 'NAM'
  def fetch_todays_mos(model,hourstring)
    date = Date.today.to_s
    hash_array = Array.new
    url = "http://mesonet.agron.iastate.edu/mos/csv.php?station=#{self.name}&  \
      runtime=#{date}%20#{hourstring}&model=#{model}".gsub(" ","")
    forecast = Station.parse_forecast(url)
    forecast_hash = Station.make_mos_hash(forecast)
    if forecast_hash.empty?
      date = (Date.today - 1.day).to_s
      url = "http://mesonet.agron.iastate.edu/mos/csv.php?station=#{self.name}&  \
        runtime=#{date}%20#{hourstring}&model=#{model}".gsub(" ","")
      forecast = Station.parse_forecast(url)
      forecast_hash = Station.make_mos_hash(forecast)
    end
    return forecast_hash,date
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
  def self.make_mos_hash(data)
    hash_array = Array.new
    data.each {|row| hash_array << {:model => row[1], :runtime => row[2], :ftime => row[3], :tmp => row[5], \
    :dpt => row[6], :cld => row[7], :wdr => row[8], :wsp => row[9]}}
    return hash_array
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
    #call self.fetch_mos to build array of hashes, sort that by :ftime, process data, spit it out
    sorted_array = self.fetch_todays_mos(model,timestring).sort_by {|hash| hash[:ftime]}
    final_array = self.process_sorted_mos_array(sorted_array,field)
  end
#-----------------------------------------------------------------------------------------------

  #loop through array, find duplicates, average values, delete extraneous records
  #loop has to run twice to remove all duplicates! 's' is shorthand for sorted_array (to save space)
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

#------------------------------------------------------------------------------------------------------


     ###########################################################################################
     ################### END FORECAST TIME SERIES FUNCTIONS #######################################
     ###########################################################################################




#--------------------------------------------------------------------------------------------------------

     #############################################################################################
     ################### OBSERVATION TIME SERIES FUNCTIONS ##########################################
     #############################################################################################

#-------------------------------------------------------------------------------------------------------

  #grabs sfc obs, calls self.parse_obs and self.make_obs_hash
  def fetch_past_obs(userfield)
    begin_day, begin_month, begin_year, end_day, end_month, end_year = Station.get_date_info
    url =  "http://mesonet.agron.iastate.edu/cgi-bin/request/getData.py?station=#{self.name[1..3]}& \
    data=tmpf&data=dwpf&data=relh&data=drct&data=sknt&data=p01i&data=mslp&&data=skyc1& \
    year1=#{begin_year}&year2=#{end_year}&month1=#{begin_month}&month2=#{end_month}&day1=#{begin_day}&\
    day2=#{end_day}&tz=GMT&format=comma&latlon=no".gsub!(/\s+/,"")
    puts "#{url}"
    obs = Station.parse_obs(url)
    ob_hash = Station.make_obs_hash(obs)
    output = Station.prep_obs_array(ob_hash,userfield)
  end

#----------------------------------------------------------------------------------------------------------

  #do some date processing to get values which are input into the query string in 'fetch_past_obs'
  def self.get_date_info
    begin_date = Date.today
    begin_year = begin_date.year.to_s
    begin_month = begin_date.month.to_s
    begin_day = begin_date.day.to_s
    end_date = Date.today
    end_year = end_date.year.to_s
    end_month = end_date.month.to_s
    end_day = end_date.day.to_s
    return begin_day, begin_month, begin_year, end_day, end_month, end_year
  end

#-----------------------------------------------------------------------------------------------------------

  #connect to webpage with data, split it into arrays, map to new variable, delete headerlines
  def self.parse_obs(url)
    require 'open-uri'
    data = Nokogiri.HTML(open(url)).text.split("\n").to_a.map {|row| row.split(',')}
    4.times {|i| data.delete_at(0)}
    puts data[0]
    return data
  end
#------------------------------------------------------------------------------------------------------------

  #input the obs_data from 'self.parse_obs' function. output a hash array
  def self.make_obs_hash(data)
    hash_array = []
    data.each {|row| hash_array << {:vtime => row[1], :tmp => row[2], :dpt => row[3],:wdr => row[5], :wsp => row[6] }}
    return hash_array
  end
#----------------------------------------------------------------------------------------------------------

  #input the desired field and the obs_hash defined above in 'self.make_obs_hash'
  def self.prep_obs_array(obs_hash,field)
    view_data = obs_hash.map do |row|
      [row[:vtime].to_datetime.to_i*1000, row[field.to_sym].to_f]
    end
  end

#--------------------------------------------------------------------------------------------------------

  #get data from obs for past 6 hrs
  #def get_obs_from_past_6hrs(hash,field)
  #  six_hr_threshold = (Time.now - 6.hours).datetime.to_i
  #  output_array = Array.new
  #  hash.each do |row|
  #    if row[:ftime.to_datetime.to_i]>six_hr_threshold
  #      output_array.push(row)
  #    end
  #  end
  #end

#--------------------------------------------------------------------------------------------------------
     #############################################################################################
     ################### WINDROSE PROCESSING FUNCTIONS ##########################################
     #############################################################################################
#--------------------------------------------------------------------------------------------------------


  #will fetch mos wind data for the past few days (excluding today)
  #this data will be compared to the observed data over the same timeframe
  def make_forecasted_windrose(forecast_array)
    hash_array = Station.prep_wind_forecast(forecast_array).compact
    sorted_data = Station.sort_wind_data(hash_array)
    view_data = Station.process_windrose_data_from(sorted_data)
  end  #input the hash_array with the forecast data, pull out the wdr data, sort it into bins [N,NE,E,SE,...,W,NW]
  #------------------------------------------------------------------------------------------------------------

  #loop over forecast data and for each row, create a hash {:wdr=>'XXX',:wsp=>'XX'}
  #output is an array of hashes like this... [{:wdr=>'220',:wsp=>'19'},......]
  def self.prep_wind_forecast(forecast)
    output = forecast.map do |row|
        {:wdr => row[:wdr], :wsp => row[:wsp]}
    end
    return output
  end

  #fetch_obs, make the hash of wind data, sort it into bins (N,NE,E...), then loop over each bin and
  #compute the average value of all wind data for that bin
  def make_observed_windrose()
    obs = self.fetch_past_obs("wsp")
    hash = Station.make_obs_windrose_hash(obs)
    sorted_data = Station.sort_wind_data(hash)
    view_data = Station.process_windrose_data_from(sorted_data)
  end
#-------------------------------------------------------------------------------------------------------

  #create a hash_array containing wdr and wsp, send this output into the sort_wind_data function
  def self.make_obs_windrose_hash(obs)
    output = obs.map do |row|
      {:wdr => row[:wdr], :wsp => row[:wsp]}
    end
  end

  #sort the wind data into bins. [337.5-22.49 = 'N', 22.5-67.49='NE',....]
  def self.sort_wind_data(hash)
    binned_data = Array.new
    n = hash.map {|row| if row[:wdr].to_f.between?(0,22.49)&&row[:wdr].to_f.between?(337.5,360) then row[:wsp].to_f end}
    ne = (hash.map {|row| if row[:wdr].to_f.between?(22.5,67.49) then row[:wsp].to_f end})
    e = (hash.map {|row| if row[:wdr].to_f.between?(67.5,112.49) then row[:wsp].to_f end})
    se = (hash.map {|row| if row[:wdr].to_f.between?(112.5,157.49) then row[:wsp].to_f end})
    s = (hash.map {|row| if row[:wdr].to_f.between?(157.5,202.49) then row[:wsp].to_f end})
    sw = (hash.map {|row| if row[:wdr].to_f.between?(202.5,247.49) then row[:wsp].to_f end})
    w = (hash.map {|row| if row[:wdr].to_f.between?(247.5,292.49) then row[:wsp].to_f end})
    nw = (hash.map {|row| if row[:wdr].to_f.between?(292.5,337.49) then row[:wsp].to_f end})
    binned_data.push(n,ne,e,se,s,sw,w,nw)
    output_array = binned_data.map {|row| row.compact}
    return output_array
  end
#----------------------------------------------------------------------------------------------------

  #input the sorted wind data, average out the values for each bin and shove the results into an array
  def self.process_windrose_data_from(wsp_hash)
    #each bin is a predefined set of angles found in the 'sort_wind_data' function right above this
    #the output will be an array, each slot filled with the average windspeed for that bin
    output = Array.new
    #loop over each bin. find average of all elements in each row (sometimes there are zero!)
    0.upto(7) do |bin|
      sum = 0
      if wsp_hash[bin].length == 0
        avg = 0
      else
        wsp_hash[bin].each {|s| sum = sum + s}
        avg = (sum/wsp_hash[bin].length).round(2)
      end
      output.push(avg)
    end
    return output
  end
#----------------------------------------------------------------------------------------------------

end #endclass

