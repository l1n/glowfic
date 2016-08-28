class CrudController < ApplicationController
  before_filter :login_required, only: [:new, :create, :edit, :update, :destroy]
  before_filter :find_model, only: [:show, :edit, :update, :destroy]
  before_filter :require_permission, only: [:edit, :update, :destroy]

  def index
    @page_title = controller_name.titlecase
  end

  def new
    @model = model_class.new
    @page_title = "New #{model_name}"
    set_model
  end

  def create
    @model = model_class.new(params[controller_name.singularize])
    if @model.save
      flash[:success] = "#{controller_name} created successfully."
      redirect_to model_path(@model) and return
    end


    flash.now[:error] = {}
    flash.now[:error][:message] = "Continuity could not be created."
    flash.now[:error][:array] = @board.errors.full_messages
    @page_title = "New Continuity"
    set_available_cowriters
    render :action => :new
  end

  def show
  end

  def edit
  end

  def update
  end

  def destroy
    @model.destroy
    flash[:success] = "#{controller_name} deleted successfully."
    redirect_to models_path
  end

  protected

  def find_model
    unless @model = model_class.find_by_id(params[:id])
      flash[:error] = "#{model_name} could not be found."
      redirect_to models_path and return
    end
    set_model
  end

  def require_permission
    return unless model_class.method_defined? :editable_by?
    unless @model.editable_by?(current_user)
      flash[:error] = "You do not have permission to edit this #{controller_name.singularize}."
      redirect_to model_path(@model)
    end
  end

  def model_name
    @mn ||= controller_name.classify
  end

  def model_class
    @mc ||= model_name.constantize
  end

  def model_path(model)
    send("#{controller_name.singularize}_path", model)
  end

  def models_path
    @msp ||= send("#{controller_name}_path")
  end

  def set_model
    instance_variable_set("@#{controller_name.singularize}", @model)
  end
end
