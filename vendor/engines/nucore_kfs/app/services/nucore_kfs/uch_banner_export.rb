module NucoreKfs

  class UchBannerExport
    include Rails.application.routes.url_helpers

    def initialize(uch_journal_rows)
      @uch_journal_rows = uch_journal_rows
    end

    def generate_report(csv_file_path)
      CSV.open(csv_file_path, "wb") do |csv|
        keys = @uch_journal_rows.first.keys
        csv << keys
        @uch_journal_rows.each do |hash|
          csv << hash.values_at(*keys)
        end
      end
    end

    def to_csv()

      headers = ['Order ID', 'Line Item ID', 'Order URL', 'Banner Index #', 'Amount', 'Transaction Date']
  
      CSV.generate(headers: true) do |csv|
        csv << headers
  
        @uch_journal_rows.each do |row|
          url_for_order = order_url(row&.order_detail&.order_id)
          rowdata = [
            row&.order_detail&.order_id,
            row&.order_detail&.id,
            url_for_order,
            row&.order_detail&.account&.account_number,
            row&.order_detail&.actual_cost,
            row&.order_detail&.created_at&.strftime("%Y-%m-%d")
          ]
          csv << rowdata
        end
      end
    end
    
  end
end
