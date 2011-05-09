class FacilityAccountsController < ApplicationController
  admin_tab     :all
  before_filter :authenticate_user!
  before_filter :check_acting_as
  before_filter :init_current_facility

  load_and_authorize_resource :class => Account

  layout 'two_column'

  def initialize
    @active_tab = 'admin_invoices'
    super
  end

  # GET /admin_accounts
  def index
    # list accounts that have ordered in the facility
    @accounts = current_facility.order_details.accounts.paginate(:page => params[:page])    
  end

  # GET /facilties/:facility_id/accounts/:id
  def show
    @account = Account.find(params[:id])
  end

  # GET /facilities/:facility_id/accounts/new
  def new
    @owner_user = User.find(params[:owner_user_id])
    @account    = @owner_user.accounts.new(:expires_at => Time.zone.now + 1.year)
  end

  # GET /facilities/:facility_id/accounts/:id/edit
  def edit
    @account = Account.find(params[:id])
  end
  
  # PUT /facilities/:facility_id/accounts/:id
  def update
    @account     = Account.find(params[:id])
    class_params = params[:account] || params[:credit_card_account] || params[:purchase_order_account] || params[:nufs_account]
    if @account.update_attributes(class_params)
      flash[:notice] = 'The payment source was successfully updated.'
      redirect_to facility_account_url
    else
      render :action => "edit"
    end
  end

  # POST /facilities/:facility_id/accounts
  def create
    class_params        = params[:account] || params[:credit_card_account] || params[:purchase_order_account] || params[:nufs_account]
    @owner_user         = User.find(params[:owner_user_id])
    @account            = Class.const_get(params[:class_type]).new(class_params)
    @account.created_by = session_user.id
    @account.account_users_attributes = [{:user_id => params[:owner_user_id], :user_role => 'Owner', :created_by => session_user.id }]
    case @account.class.name
      when 'PurchaseOrderAccount'
        @account.facility_id = current_facility.id
      when 'CreditCardAccount'
        begin
          @account.expires_at = Date.civil(class_params[:expiration_year].to_i, class_params[:expiration_month].to_i, -1)
        rescue Exception => e
        end
      when 'NufsAccount'
        # set temporary expiration to be updated later
        @account.valid? # populate virtual charstring attributes required by set_expires_at
        @account.set_expires_at
    end

    if @account.save
      flash[:notice] = 'Account was successfully created.'
      redirect_to(user_accounts_url(current_facility, @account.owner_user)) and return
    else
      render :action => 'new'
    end
  end

  def new_account_user_search
  end

  def user_search
  end

  # GET /facilities/:facility_id/accounts/search
  def search
    flash.now[:notice] = 'This page is not yet implemented'
  end

  # GET/POST /facilities/:facility_id/accounts/search_results
  def search_results
    term   = generate_multipart_like_search_term(params[:search_term])
    if params[:search_term].length >= 3
      conditions = ["LOWER(first_name) LIKE ? OR LOWER(last_name) LIKE ? OR LOWER(username) LIKE ? OR LOWER(CONCAT(first_name, last_name)) LIKE ?", term, term, term, term]
      @users     = User.find(:all, :conditions => conditions, :order => 'last_name, first_name')
      if @users.length > 0
        @accounts = @users.collect{|u| u.account_users.find(:all, :conditions => ['account_users.deleted_at IS NULL AND user_role = ?', 'Owner'], :include => :account).collect{|au| au.account}}.flatten
      end
      if @accounts.nil? || @accounts.empty?
        @accounts = Account.find(:all, :conditions => ['account_number like ?', term], :order => 'type, account_number')
      end
      @accounts = @accounts.paginate(:page => params[:page]) #hash options and defaults - :page (1), :per_page (30), :total_entries (arr.length)
    else
      flash.now[:errors] = 'Search terms must be 3 or more characters.'
    end
    respond_to do |format|
      format.html { render :layout => false }
    end
  end

  def user_accounts
    @user = User.find(params[:user_id])
  end

  # GET /facilities/:facility_id/accounts/credit_cards
  def credit_cards
    @subnav     = 'billing_nav'
    @active_tab = 'admin_invoices'
    @accounts   = CreditCardAccount.find(:all).reject{|a| a.facility_balance(current_facility) <= 0}

    if @accounts.empty?
      flash.now[:notice] = 'There are no pending credit card transactions'
    else
      selected_id=params[:selected_account]

      if selected_id.blank?
        @selected=@accounts.first
      else
        @accounts.each{|a| @selected=a and break if a.id == selected_id.to_i }
      end
    end

    @unreconciled_details=OrderDetail.account_unreconciled(current_facility, @selected)
    @unreconciled_details=@unreconciled_details.paginate(:page => params[:page])
  end

  #POST /facilities/:facility_id/accounts/update_credit_cards
  def update_credit_cards
    @error_fields = {}
    update_details = OrderDetail.find(params[:order_detail].keys)

    OrderDetail.transaction do
      count = 0
      update_details.each do |od|
        od_params = params[:order_detail][od.id.to_s]
        od.reconciled_note=od_params[:notes]

        begin
          if od_params[:reconciled] == '1'
            od.to_reconciled!
            count += 1
          else
            od.save!
          end
        rescue
          @error_fields = {od.id => od.errors.collect { |field,error| field}}
          errors = od.errors.full_messages
          errors = [$!.message] if errors.empty?
          flash.now[:error] = (['There was an error processing the credit card payments'] + errors).join("<br />")
          raise ActiveRecord::Rollback
        end
      end

      flash[:notice] = "#{count} payment#{count == 1 ? '' : 's'} successfully reconciled" if count > 0
    end

    redirect_to credit_cards_facility_accounts_path(current_facility)
  end

  # GET /facilities/:facility_id/accounts/purchase_orders
  def purchase_orders
    @subnav     = 'billing_nav'
    @active_tab = 'admin_invoices'
    @accounts   = PurchaseOrderAccount.find(:all).reject{|a| a.facility_balance(current_facility) <= 0}
    flash.now[:notice] = 'There are no pending purchase order transactions' if @accounts.empty?
  end

  # POST /facilities/:facility_id/accounts/update_purchase_orders
  def update_purchase_orders
    @subnav     = 'billing_nav'
    @active_tab = 'admin_invoices'

    @error_fields = {}
    update_accounts = PurchaseOrderAccount.find(params[:account].keys)
    AccountTransaction.transaction do
      count = 0
      update_accounts.each do |a|
        a_params = params[:account][a.id.to_s]
        next unless a_params[:reference].length > 0 && a_params[:transaction_amount].length > 0
        at = a.payment_account_transactions.new({
          :facility_id        => current_facility.id,
          :description        => a_params[:notes],
          :transaction_amount => a_params[:transaction_amount].to_f * -1,
          :created_by         => session_user.id,
          :finalized_at       => Time.zone.now,
          :reference          => a_params[:reference],
          :is_in_dispute      => false,
        })
        begin
          at.save!
          count += 1
        rescue
          @error_fields = {a.id => at.errors.collect { |field,error| field}}
          errors = at.errors.full_messages
          errors = [$!.message] if errors.empty?
          flash.now[:error] = (['There was an error processing the purchase order payments'] + errors).join("<br />")
          raise ActiveRecord::Rollback
        end
      end
      flash[:notice] = "#{count} payment#{count == 1 ? '' : 's'} successfully processed" if count > 0
      redirect_to purchase_orders_facility_accounts_path
      return
    end
    @accounts = PurchaseOrderAccount.find(:all).reject{|a| a.facility_balance(current_facility) <= 0}
    render :action => "purchase_orders"
  end

  # GET /facilities/:facility_id/accounts/:account_id/members
  def members
    @account = Account.find(params[:account_id])
  end

  # GET /facilities/:facility_id/accounts/:account_id/statements/:statement_id
  def show_statement
    @account = Account.find(params[:account_id])
    @facility = current_facility
    action='show_statement'

    case params[:statement_id]
      when 'list'
        action += '_list'
        @statements = @account.statements.final_for_facility(current_facility).uniq
        @statements = @statements.paginate(:page => params[:page])
      when 'recent'
        @order_details = @account.order_details.for_facility(@facility)
        @order_details = @order_details.paginate(:page => params[:page])
      else
        prawnto :prawn => {
          :left_margin   => 50,
          :right_margin  => 50,
          :top_margin    => 50,
          :bottom_margin => 75
        }

        @statement=Statement.find(params[:statement_id].to_i)
    end

    respond_to do |format|
      format.html { render :action => action }
      format.pdf  { render :template => '/statements/show' }
    end
  end
  
  # GET /facilities/:facility_id/accounts/:account_id/suspend
  def suspend
    @account = Account.find(params[:account_id])
    if @account.suspend!
      flash[:notice] = "Payment source suspended successfully"
    else
      flash[:notice] = "An error was encountered while suspending the payment source"
    end
    redirect_to facility_account_path(current_facility, @account)
  end

  # GET /facilities/:facility_id/accounts/:account_id/unsuspend
  def unsuspend
    @account = Account.find(params[:account_id])
    if @account.unsuspend!
      flash[:notice] = "Payment source activated successfully"
    else
      flash[:notice] = "An error was encountered while activating the payment source"
    end
    redirect_to facility_account_path(current_facility, @account)
  end
end
