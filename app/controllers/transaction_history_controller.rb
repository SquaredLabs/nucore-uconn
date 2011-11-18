class TransactionHistoryController < ApplicationController
  #layout 'application'
  #layout 'two_column', :except => [:my_history, :account_history]
  admin_tab     :all
  customer_tab :my_history, :account_history
  
  include DateHelper
  before_filter :authenticate_user!
  before_filter :check_acting_as
  
  before_filter :remove_ugly_params
   
  def my_history
    @accounts = session_user.accounts
    @facilities = Facility.active
    
    @search_fields = params.merge({
      :accounts => get_allowed_accounts(@accounts, params[:accounts])
    })
    do_search(@search_fields)
    add_optimizations
    @order_details = @order_details.paginate(:page => params[:page])
  end
  
  def account_history
    @account = Account.find(params[:account_id])
    @accounts = [@account]
    @facilities = @account.facilities
    
    @search_fields = params.merge({
      :accounts => [@account]
    })
    do_search(@search_fields)
    add_optimizations
    @order_details = @order_details.paginate(:page => params[:page])
    
  end
  
  def facility_history
    find_with_facility
    @order_details = @order_details.paginate(:page => params[:page])
    @active_tab = 'admin_transactions'
    render :layout => 'two_column'
  end
    
  def in_review
    find_with_facility
    @order_details = @order_details.in_review(@facility)
    @order_details = @order_details.reorder(:reviewed_at)
    @order_detail_action = :in_review
    @active_tab = 'admin_transactions'
    render :layout => 'two_column'
  end
  
  def notifications
    find_with_facility
    @order_details = @order_details.need_notification(@facility)
    @order_detail_action = :notifications
    @active_tab = 'admin_transactions'
    render :layout => 'two_column'
  end
  
  def find_with_facility
    @current_facility = @facility = Facility.find_by_url_name(params[:facility_id])
    raise ActiveRecord::RecordNotFound unless @facility
    @facilities = [@facility]
    @accounts = Account.for_facility(@facility)
    
    @search_fields = params.merge({
      :accounts => get_allowed_accounts(@accounts, params[:accounts]),
      :facilities => @facilities
    })
    
    do_search(@search_fields)
    add_optimizations
  end
     
  private
  
  def do_search(search_params)
    Rails.logger.debug "search: #{search_params}"
    @order_details = OrderDetail.joins(:order).ordered
    @order_details = @order_details.for_accounts(search_params[:accounts])
    
    start_date = parse_usa_date(search_params[:start_date].to_s.gsub("-", "/"))
    end_date = parse_usa_date(search_params[:end_date].to_s.gsub("-", "/"))  
    
    @order_details = @order_details.for_facilities(search_params[:facilities]).
      fulfilled_in_date_range(start_date, end_date).
      order_by_desc_nulls_first(:fulfilled_at)    
  end
  
  def remove_ugly_params
    if (params[:commit])
      params.delete(:commit)
      params.delete(:utf8)
      redirect_to params
      return false
    end
  end
    
  def get_allowed_accounts(allowed_accounts, search_accounts)
    search_accounts ||= []
    allowed_accounts = allowed_accounts.map{|a| a.id.to_s}
    denyed_accounts = search_accounts - allowed_accounts
    search_accounts - denyed_accounts
  end
  
  def add_optimizations
    # cut down on some n+1s
    @order_details = @order_details.
        includes(:order => :facility).
        includes(:account).
        includes(:product).
        includes(:order_status).
        includes(:reservation).
        includes(:order => :user).
        includes(:price_policy)
        
  end
  
end
