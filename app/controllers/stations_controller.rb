class StationsController < ApplicationController
  def index
     @states = (Station.all.map {|s| s.state}).sort.uniq

    #The first step is to get the @userstate.
    if params[:userstate].blank?
      #do nothing
    elsif !params[:userstate].blank?
      #if we have user input for a state, save it to session variable
      @userstate = params[:userstate]
      session[:userstate] = @userstate
      @stations = add_stations_from(session[:userstate])
    end

      #hack here, kept getting errors about the @stations variable
      #being empty. The view was complaining about it! So if it is blank
      #(ie the user just loaded a list of stations via the 'selectstate' button
      #and there is no input for either the station or field) fill it up with
      #the stations corresponding to the session variable 'userstate'.
    if params[:userstation].blank? || params[:userfield].blank?
      #don't do anything except make the @stations to prevent errors
      @stations = add_stations_from(session[:userstate])
    else
      #add correct stations, save userstate and userfield as session variables,
      #create instance
      @stations = add_stations_from(session[:userstate])
      session[:userstation] = params[:userstation]
      @userstation = params[:userstation]
      @userfield = params[:userfield]
      session[:userfield] = params[:userfield]
      @station = Station.find_by_name(@userstation.to_s)

      @gfs0Z = Station.prep_mos_array(@station.blend_forecast("GFS", "00:00", @userfield),@userfield)
      @gfs06Z = Station.prep_mos_array(@station.blend_forecast("GFS", "06:00", @userfield),@userfield)
      @gfs12Z = Station.prep_mos_array(@station.blend_forecast("GFS", "12:00", @userfield),@userfield)
      @gfs18Z = Station.prep_mos_array(@station.blend_forecast("GFS", "18:00", @userfield),@userfield)
      @nam0Z = Station.prep_mos_array(@station.blend_forecast("NAM", "00:00", @userfield),@userfield)
      @nam12Z = Station.prep_mos_array(@station.blend_forecast("NAM", "12:00", @userfield),@userfield)

      @obs = Station.prep_obs_array(@station.fetch_past_obs(), @userfield)

      if params[:userfield]=="tmp" then @var="Temperature [F]"
      elsif params[:userfield]=="dpt" then @var="Dewpoint [F]"
      elsif params[:userfield]=="wdr" then @var="Wind Direction [deg]"
      elsif params[:userfield]=="wsp" then @var="Wind Speed [knots]"
      end



      @titlestring = "#{@station.longname}-#{@station.state} #{Date.today.to_s} MOS Verification Forecast (UTC time)"
    end
  end

  def windrose
    @message = "did it mom"
  end

  def add_stations_from(state)
     stations = Station.where(:state=>state).map do |s|
       ["#{s.name},  #{s.longname.titleize}", s.name.to_sym]
     end
     return stations
  end
end
