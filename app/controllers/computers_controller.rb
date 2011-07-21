class ComputersController < ApplicationController
  before_filter :require_valid_unit
  require 'cgi'

  def index
    # Set environment at view layer
    @computers = ComputerService.collect(params,current_unit,current_environment)
    
    respond_to do |format|
      format.html # index.html
      format.js # index.js
    end
  end

  def new
    @computer = Computer.new({:unit_id => current_unit.id})
    
    respond_to do |format|
      format.html
      format.js { render :action => "edit" }
    end
  end

  def create
    @computer = Computer.new(params[:computer].merge({:unit_id => current_unit.id}))
    
    respond_to do |format|
      if @computer.save
        flash[:notice] = "#{@computer} was successfully created."
        format.html { redirect_to computer_path(@computer.unit, @computer) }
      else
        flash[:error] = "Failed to create #{@computer} computer object!"
        format.html { render :action => "new"}
      end
    end
  end
  
  def show
    @computer = Computer.find_for_show(params[:unit], CGI::unescape(params[:id]))
    
    respond_to do |format|
      if @computer.present?
        format.html
        format.manifest { render :text => @computer.to_plist}
        format.plist { render :text => @computer.to_plist}
        format.client_prefs { render :text => @computer.client_prefs.to_plist }
      else
        MissingManifest.new({:manifest_type => Computer.to_s, :identifier => params[:id], :request_ip => request.remote_ip}).save
        format.manifest { render :file => "public/404.html", :status => 404, :layout => false}
        format.html { render :file => "public/404.html", :status => 404, :layout => false }
      end
    end
  end

  def edit
    @computer = Computer.find_for_show(params[:unit], CGI::unescape(params[:id]))
  end

  def update
    @computer = Computer.find_for_show(params[:unit], CGI::unescape(params[:id]))
    
    respond_to do |format|
      if @computer.update_attributes(params[:computer])
        flash[:notice] = "#{@computer.name} was successfully updated."
        format.html { redirect_to computer_path(@computer.unit, @computer) }
      else
        flash[:error] = 'Could not update computer!'
        format.html { render :action => "edit" }
      end
    end 
  end

  def destroy
    @computer = Computer.find_for_show(params[:unit], CGI::unescape(params[:id]))
    
    if @computer.destroy
      flash[:notice] = "Computer was destroyed successfully"
    end
    
    respond_to do |format|
      format.html { redirect_to computers_path(current_unit) }
    end
  end


  # Import an ARD plist form
  def import
  end
  
  # Take ARD plist and create new computer objects
  # TO-DO when a computer object import fails, tell
  # the user what went wrong (by print the computer.errors hash)
  def create_import
    begin
      @computers = ComputerService.import(params[:computer],current_unit)
    rescue NoMethodError
      e = "Please select a plist file"
    rescue => e
    end
      
    unless @computers.nil?
      @total = @computers.count
      # Save each computer.  If it doesn't save, leave it out of the array
      @computers = @computers.collect {|e| e if e.save}.compact
    end
    
    respond_to do |format|
      if @computers.nil?
        flash[:error] = "There was a problem while parsing the plist: #{e}"
        format.html { redirect_to import_new_computer_path(current_unit) }
      elsif @computers.count > 0
        flash[:notice] = "#{@computers.count} of #{@total} computers imported into #{@computers.first.computer_group}"
        format.html { redirect_to computers_path(current_unit) }
      else
        flash[:warning] = "Zero computers were imported.  Did the ARD list have any members?"
        format.html { redirect_to computers_path(current_unit) }
      end
    end
  end
  
  # Allows a computer to checkin with the server, notifying it
  # of the last successful munki run.  May be extended in the future.
  def checkin
    @computer = Computer.find_for_show(nil, params[:id])
    
    if params[:managed_install_report_plist].present?
      report_hash = ManagedInstallReport.format_report_plist(params[:managed_install_report_plist]).merge({:ip => request.remote_ip})
      @computer.managed_install_reports.build(report_hash)
    end
    
    if params[:system_profiler_plist].present?
      system_profile_hash = SystemProfile.format_system_profiler_plist(params[:system_profiler_plist])
      @computer.build_system_profile(system_profile_hash)
    end
    
    @computer.save
    
    @computer.warranty.destroy if @computer.serial_number != @computer.warranty.serial_number
    AdminMailer.computer_report(@computer).deliver if @computer.report_due?
    render :text => ''
  end
  
  
  # Allows multiple edits
  def edit_multiple
    @computers = Computer.find(params[:selected_records])
    @environment_id = params[:environment_id] if params[:environment_id].present?
    respond_to do |format|
      format.html
      format.js
    end
  end
  
  def update_multiple
    @computers = Computer.find(params[:selected_records])
    p = params[:computer]
    results = []
    exceptionMessage = nil
    begin
      results = Computer.bulk_update_attributes(@computers, p)
    rescue ComputerError => e
      exceptionMessage = e.to_s
    end

    respond_to do |format|
        if results.empty?
          flash[:error] = exceptionMessage
          format.html { redirect_to(:action => "index") }
        elsif !results.include?(false)
          flash[:notice] = "All #{results.length} computer objects were successfully updated."
          format.html { redirect_to(:action => "index") }
        elsif results.include?(false) && results.include?(true)
          flash[:warning] = "#{results.delete_if {|e| e}.length} of #{results.length} computer objects updated."
          format.html { redirect_to(:action => "index") }
        elsif !results.include?(true)
          flash[:error] = "None of the #{results.length} computer objects were updated !"
          format.html { redirect_to(:action => "index") }
        end
    end
  end
  
  def environment_change
    if params[:computer_id] == "new"
      @computer = Computer.new({:unit_id => current_unit.id})
    else
      @computer = Computer.find(params[:computer_id])
    end
    
    @environment_id = params[:environment_id] if params[:environment_id].present?
    
    respond_to do |format|
      format.js
    end
  end
  
  
  def update_warranty
    @computer = Computer.find_for_show(params[:unit], params[:computer_id])
    
    @computer.warranty.delete if @computer.warranty.present?
    @computer.warranty = nil
    
    if @computer.serial_number.nil?
      flash[:error] = "Cannot find a warranty for #{@computer.name} without a serial number."
    else
      warranty_hash = Warranty.get_warranty_hash(@computer.serial_number)
      warnt = @computer.build_warranty(warranty_hash)
      if warnt.save
        flash[:notice] = "#{@computer.name}'s warranty was successfully updated."
      else
        flash[:error] = "#{@computer.name}'s warranty was not updated."
      end
    end
    redirect_to computer_path(@computer.unit, @computer, anchor: 'warranty_tab')   
  end
end
