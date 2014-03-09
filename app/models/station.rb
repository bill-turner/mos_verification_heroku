class Station < ActiveRecord::Base
has_many :observations

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
    #if forecast_hash.empty?
    #  date = (Date.today - 1.day).to_s
    #  url = "http://mesonet.agron.iastate.edu/mos/csv.php?station=#{self.name}&  \
    #    runtime=#{date}%20#{hourstring}&model=#{model}".gsub(" ","")
    #  forecast = Station.parse_forecast(url)
    #  forecast_hash = Station.make_mos_hash(forecast)
    #end
    return forecast_hash
  end
#------------------------------------------------------------------------------------------

  #take in a urlstring, parse page with nokogiri, delete first row(headers), return the array of arrays
  def self.parse_forecast(url)
    require 'open-uri'
    data = Nokogiri.HTML(open(url)).text.split("\n").to_a.map {|row| row.split(',')}
    data.delete_at 0
    return data
  end
#-------------------------------------------------------------------------------------

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
     ################ HISTORICAL OBSERVATION DATA FUNCTIONS ##########################################
     #############################################################################################

#-------------------------------------------------------------------------------------------------------

  #grabs sfc obs, calls self.parse_obs and self.make_obs_hash
  def fetch_past_obs(userfield)
    begin_day, begin_month, begin_year, end_day, end_month, end_year = Station.get_date_info
    url =  "http://mesonet.agron.iastate.edu/cgi-bin/request/getData.py?station=#{self.name[1..3]}& \
    data=tmpf&data=dwpf&data=drct&data=sknt&data=p01i \
    year1=2011&year2=2013&month1=1&month2=12&day1=1&day2=31&tz=GMT&format=comma&latlon=no".gsub!(/\s+/,"")
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



#--------------------------------------------------------------------------------------------------------
     #####################################################################################################
     #################  3 DAY OBHISTORY FUNCTIONS #######################################################
     ###################################################################################################
#--------------------------------------------------------------------------------------------------------

  #connect to the NWS 3day obhistory page and grab data from current day only!
  def self.get_todays_obs_for(name,field)
    require 'open-uri'
    url = "http://w1.weather.gov/data/obhistory/#{name}.html"
    table = Nokogiri.HTML(open(url)).xpath('//table[4]//tr//td')
    zone = Nokogiri.HTML(open(url)).xpath('//table[4]//th').text[9..11]
    b_o_d = Time.now.beginning_of_day
    hash_array = []

    table.each_slice(18) do |row|
      flag_time = Time.new(b_o_d.year,b_o_d.month,b_o_d.day,0,0,0,b_o_d.utc_offset/60/60)

      day = row[0].text.to_i
      time = row[1].text
      hours = time[0..1].to_i
      minutes = time[3..4].to_i
      tmp = row[6].text.to_f
      dwp = row[7].text.to_f
      wsp = row[8].text.scan(/\d+/)[0].to_f

      processed_row = process_row_with_timezone(zone,b_o_d,day,hours,minutes,tmp,dwp,wsp)
      row_time = processed_row[0]

      if row_time>flag_time
        hash_array.push(:time => row_time,:tmp => tmp, :dwp => dwp, :wsp => wsp)
      end

    end
    view_data = prep_hash_array_for_view(hash_array,field)
  end

  #need to create the timestamp for the row by adding the UTC OFFSET
  #output will be an array will neccessary data [dtstring,tmp,dwp,wsp]
  def self.process_row_with_timezone(zone,bod,day,hours,minutes,tmp,dwp,wsp)
    if zone=='edt'
      t = Time.new(bod.year,bod.month,day,hours,minutes,0,"-04:00")
      output = [t,tmp,dwp,wsp]
    elsif zone=='est'
      t = Time.new(bod.year,bod.month,day,hours,minutes,0,"-05:00")
      output = [t,tmp,dwp,wsp]
    elsif zone=='cdt'
      t = Time.new(bod.year,bod.month,day,hours,minutes,0,"-05:00")
      output = [t,tmp,dwp,wsp]
    elsif zone=='cst'
      t = Time.new(bod.year,bod.month,day,hours,minutes,0,"-06:00")
      output = [t,tmp,dwp,wsp]
    elsif zone=='mdt'
      t = Time.new(bod.year,bod.month,day,hours,minutes,0,"-06:00")
      output = [t,tmp,dwp,wsp]
    elsif zone=='mst'
      t = Time.new(bod.year,bod.month,day,hours,minutes,0,"-07:00")
      output = [t,tmp,dwp,wsp]
    elsif zone=='pdt'
      t = Time.new(bod.year,bod.month,day,hours,minutes,0,"-07:00")
      output = [t,tmp,dwp,wsp]
    elsif zone=='pst'
      t = Time.new(bod.year,bod.month,day,hours,minutes,0,"-08:00")
      output = [t,tmp,dwp,wsp]
    elsif zone=='akdt'
      t = Time.new(bod.year,bod.month,day,hours,minutes,0,"-08:00")
      output = [t,tmp,dwp,wsp]
    elsif zone=='akst'
      t = Time.new(bod.year,bod.month,day,hours,minutes,0,"-09:00")
      output = [t,tmp,dwp,wsp]
    end
    return output
  end

  def self.prep_hash_array_for_view(hash_array,field)
    view_data = hash_array.map do |h|
      [h[:time].to_datetime.to_i*1000, h[field.to_sym]]
    end
  end



#--------------------------------------------------------------------------------------------------------
     #############################################################################################
     ################### windrose processing functions ##########################################
     #############################################################################################
#--------------------------------------------------------------------------------------------------------

#
#  #will fetch mos wind data for the past few days (excluding today)
#  #this data will be compared to the observed data over the same timeframe
#  def make_forecasted_windrose(forecast_array)
#    hash_array = station.prep_wind_forecast(forecast_array).compact
#    sorted_data = station.sort_wind_data(hash_array)
#    view_data = station.process_windrose_data_from(sorted_data)
#  end  #input the hash_array with the forecast data, pull out the wdr data, sort it into bins [n,ne,e,se,...,w,nw]
#  #------------------------------------------------------------------------------------------------------------
#
#  #loop over forecast data and for each row, create a hash {:wdr=>'xxx',:wsp=>'xx'}
#  #output is an array of hashes like this... [{:wdr=>'220',:wsp=>'19'},......]
#  def self.prep_wind_forecast(forecast)
#    output = forecast.map do |row|
#        {:wdr => row[:wdr], :wsp => row[:wsp]}
#    end
#    return output
#  end
#
#  #fetch_obs, make the hash of wind data, sort it into bins (n,ne,e...), then loop over each bin and
#  #compute the average value of all wind data for that bin
#  def make_observed_windrose()
#    obs = self.fetch_past_obs("wsp")
#    hash = station.make_obs_windrose_hash(obs)
#    sorted_data = station.sort_wind_data(hash)
#    view_data = station.process_windrose_data_from(sorted_data)
#  end
##-------------------------------------------------------------------------------------------------------
#
#  #create a hash_array containing wdr and wsp, send this output into the sort_wind_data function
#  def self.make_obs_windrose_hash(obs)
#    output = obs.map do |row|
#      {:wdr => row[:wdr], :wsp => row[:wsp]}
#    end
#  end
#
#  #sort the wind data into bins. [337.5-22.49 = 'n', 22.5-67.49='ne',....]
#  def self.sort_wind_data(hash)
#    binned_data = array.new
#    n = hash.map {|row| if row[:wdr].to_f.between?(0,22.49)&&row[:wdr].to_f.between?(337.5,360) then row[:wsp].to_f end}
#    ne = (hash.map {|row| if row[:wdr].to_f.between?(22.5,67.49) then row[:wsp].to_f end})
#    e = (hash.map {|row| if row[:wdr].to_f.between?(67.5,112.49) then row[:wsp].to_f end})
#    se = (hash.map {|row| if row[:wdr].to_f.between?(112.5,157.49) then row[:wsp].to_f end})
#    s = (hash.map {|row| if row[:wdr].to_f.between?(157.5,202.49) then row[:wsp].to_f end})
#    sw = (hash.map {|row| if row[:wdr].to_f.between?(202.5,247.49) then row[:wsp].to_f end})
#    w = (hash.map {|row| if row[:wdr].to_f.between?(247.5,292.49) then row[:wsp].to_f end})
#    nw = (hash.map {|row| if row[:wdr].to_f.between?(292.5,337.49) then row[:wsp].to_f end})
#    binned_data.push(n,ne,e,se,s,sw,w,nw)
#    output_array = binned_data.map {|row| row.compact}
#    return output_array
#  end
##----------------------------------------------------------------------------------------------------
#
#  #input the sorted wind data, average out the values for each bin and shove the results into an array
#  def self.process_windrose_data_from(wsp_hash)
#    #each bin is a predefined set of angles found in the 'sort_wind_data' function right above this
#    #the output will be an array, each slot filled with the average windspeed for that bin
#    output = array.new
#    #loop over each bin. find average of all elements in each row (sometimes there are zero!)
#    0.upto(7) do |bin|
#      sum = 0
#      if wsp_hash[bin].length == 0
#        avg = 0
#      else
#        wsp_hash[bin].each {|s| sum = sum + s}
#        avg = (sum/wsp_hash[bin].length).round(2)
#      end
#      output.push(avg)
#    end
#    return output
#  end
#----------------------------------------------------------------------------------------------------

end #endclass

