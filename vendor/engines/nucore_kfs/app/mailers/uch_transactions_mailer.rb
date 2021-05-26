class UchTransactionsMailer < ApplicationMailer

  def transaction_email(journal)
    @journal = journal
    receipients = ['joseph.oshea@uconn.edu', 'courtney.wiley@uconn.edu']

    # Filter out journal rows to get only the ones that are relevant to use:
    #  1. they have order_detail
    #  2. they are UCH accounts
    rows = journal.journal_rows.reject { |r| r.order_detail.nil? }
    rows = rows.select do |r|
      account = Account.find(r.account_id)
      account_number = account.account_number
      is_uch = account_number.match(/^UCH-(?<acct_num>\d{0,7})/)
      is_uch
    end 

    if rows.length == 0
      return false
    end

    exporter = NucoreKfs::UchBannerExport.new(rows)
    csv_contents = exporter.to_csv
    attachments['transactions.csv'] = csv_contents

    mail(to: receipients, subject: 'UCH Banner Accounts Charged in CIDER')
  end

end
