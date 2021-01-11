module NucoreKfs

  class CollectorExport
    require "date"

    @@UCH_GLOBAL_DEBIT_ACCOUNT = 'KFS-4643530-1390'

    # Please reference the "Collector Batch Format" document for a complete
    # understanding of all the fields are formatting used here.

    def initialize
      @now = DateTime.now
      # TODO: There is a fiscal_year_begins setting that we should read and use here.
      # For now, we are just hardcoding the start of UConn's FY: July 1
      @fiscal_year = (@now.month < 7 ? @now.year : @now.year + 1).to_s

      # Always "UC"
      @chart_accounts_code = "UC"

      # "Hardcoded value supplied for each organization.  Found on KFS Organization Table."
      # this is always hardcoded to this value for CIDER. IF re-using this engine in another
      # system, this would need to be changed (should likely be refactored to configuration)
      @organization_code = "1348"

      # "Record Type" - always hardcoded to "HD"
      @header_record_type = "HD"

      # "Batch Sequence Number" - Cannot be zero. Must be unique for each transmission date.
      # this records which batch this is within the day specified by transmission_date
      # right now we hardcode to 1, but if we plan to transmit mulitple times in a given day,
      # we need to change this to increment this number accordingly.
      # WARNING: since this field is limited to 1 character wide, this cannot be greater than 9
      @batch_sequence_number = 1

      # "Email Address" - To be supplied by responsible party – preferably a department email
      # This email receives the "callbacks" to indicate success/failure for the transactions
      # sent. We set this to an email we control so that we may automatically parse those
      # emails and react accordingly.
      @email = "joseph.oshea@uconn.edu"

      # "Department Contact Person" - To be supplied by responsible party
      # This should be set to someone in the team
      @department_contact_person = "Joseph OShea"

      # "Department" - To be supplied by responsible party
      # Always set this to CORE, since that is who we are
      @department_name = "CORE"

      # "Campus Mailing Address" - hardcoded for CORE
      @campus_address = "159 Discovery Dr, Storrs, CT"

      # "Campus Code" - always "01" for Storrs campus
      @campus_code = "01"

      # "Department Contact Phone Number" - To be supplied by responsible party – format AAAEEENNNN
      @department_phone_num = "8605551234" # TODO: get this right
    end

    def generate_export_header()

      # used for "Transmission Date"
      transmission_date = @now.strftime("%Y-%m-%d")

      # Comments here designate the corresponding field in the "Collector Batch Format" document
      # in the section describing the "Header Record"
      header_record = [

        # "Fiscal Year"
        @fiscal_year.ljust(4),

        # "Chart of Accounts code"
        @chart_accounts_code.ljust(2),

        # "Organization Code"
        @organization_code.ljust(4),

        # "Filler" - intentional spaces
        " " * 5,

        # "Transmission Date"
        transmission_date.ljust(10),

        # "Record Type"
        @header_record_type.ljust(2),

        # "Batch Sequence Number" - Cannot be zero. Must be unique for each transmission date.
        # this records which batch this is within the day specified by transmission_date
        @batch_sequence_number.to_s.ljust(1),

        # "Email Address"
        @email.ljust(40),

        # "Department Contact Person" - To be supplied by responsible party
        @department_contact_person.ljust(30),

        # "Department Name"
        @department_name.ljust(30),

        # "Campus Mailing Address"
        @campus_address.ljust(30),

        # "Campus Code"
        @campus_code.ljust(2),

        # "Department Contact Phone Number"
        @department_phone_num.ljust(10),

        # "Filler" - intentional blank spaces
        " " * 2,
      ]

      return header_record.join("")
    end

    def get_debit_account(order_detail_row)
      account_number = order_detail_row.account.account_number
      is_uch = account_number.match(/^UCH-(?<acct_num>\d{0,7})/)
      is_kfs = account_number.match(/^KFS-(?<acct_num>\d{0,7})-(?<obj_code>\d{4})$/)
      if is_uch
        return @@UCH_GLOBAL_DEBIT_ACCOUNT
      elsif is_kfs
        return account_number
      else
        raise "unknown account type: #{account_number}"
      end
    end

    def create_collector_transactions_from_journal_rows(journal_rows)
      collector_transactions = []
      # An increasing sequential number beginning with zero. Should be the same for each Debit(D) and Credit(C) entry.
      document_number = 0

      journal_rows.each do |journal_row|
        next unless journal_row.order_detail
        order_detail = journal_row.order_detail
        # TODO: move some of this logic to the model?
        transaction_date = order_detail.created_at.strftime("%Y-%m-%d")
        product = order_detail.product
        facility_initials = order_detail.facility.name.scan(/([A-Z])/).join
        description = "|CORE|#{facility_initials}|#{transaction_date}|#{product.name}"[0..39]
        transaction_dollar_amount = order_detail.actual_cost.truncate(2).to_s("F")
        ref_field_1 = order_detail.order_id.to_s
        ref_field_2 = order_detail.id.to_s

        # where to take the money (the purchaser)
        debit_account_string = get_debit_account(order_detail)
        # where to send the money (the facility)
        credit_account_string = product.facility_account.account_number

        # Parse account chartstrings (e.g., KFS-1234567-1234) to get account number and object code
        raise "invalid account format: #{debit_account_string}" unless debit_account_match = debit_account_string.match(/^(?<acct_type>\w{3})-(?<acct_num>\d{0,7})-(?<obj_code>\d{4})$/)
        raise "invalid account format: #{credit_account_string}" unless credit_account_match = credit_account_string.match(/^(?<acct_type>\w{3})-(?<acct_num>\d{0,7})-(?<obj_code>\d{4})$/)
        debit_account_number = debit_account_match[:acct_num]
        credit_account_number = credit_account_match[:acct_num]
        debit_object_code = debit_account_match[:obj_code]
        credit_object_code = credit_account_match[:obj_code]

        collector_transaction = CollectorTransaction.new(
          @fiscal_year,
          debit_account_number,
          credit_account_number,
          debit_object_code,
          credit_object_code,
          document_number,
          description,
          transaction_dollar_amount,
          transaction_date,
          ref_field_1,
          ref_field_2
        )
        collector_transactions.append(collector_transaction)

        # handle any counters or aggregates
        document_number += 1
      end

      collector_transactions
    end

    def generate_export_file_new(journal_rows)
      collector_transactions = create_collector_transactions_from_journal_rows(journal_rows)

      output = ""
      records = 0
      file_amt = 0
      header_content = generate_export_header()
      output << header_content << "\n"

      collector_transactions.each do |transaction|
        output << transaction.create_debit_row_string() << "\n"
        output << transaction.create_credit_row_string() << "\n"
        records += 2 # we must count both the credit and debit row
        # the way collector works, we must "double cunt"
        file_amt += transaction.get_transaction_dollar_amount() * 2
      end

      trailer_record = generate_trailer_record(records, file_amt)
      output << trailer_record << "\n"

      return output
    end

    # This function is deprecated. We are keeping it here for reference and testing because it is
    # important that we can ensure the new way of generating files keeps the previous spec.
    def generate_export_file_deprecated(journal_rows)

      output = ""

      header_content = generate_export_header()
      output << header_content << "\n"

      records = 0
      file_amt = 0

      # An increasing sequential number beginning with zero. Should be the same for each Debit(D) and Credit(C) entry.
      doc_num = 0

      puts("there are #{journal_rows.count} journal_rows")

      journal_rows.each do |journal_row|
          od = journal_row.order_detail
          next unless journal_row.order_detail
          # TODO: move some of this logic to the model?
          prod = journal_row.order_detail.product
          facility_initials = od.facility.name.scan(/([A-Z])/).join
          date = od.created_at.strftime("%Y-%m-%d")
          aan_out = od.account.account_number
          fan_out = prod.facility_account.account_number


          raise "not a kfs account: #{aan_out}" unless aan_match = aan_out.match(/^KFS-(?<acct_num>\d{0,7})-(?<obj_code>\d{4})$/)
          raise "not a kfs account: #{fan_out}" unless fan_match = fan_out.match(/^KFS-(?<acct_num>\d{0,7})-(?<obj_code>\d{4})$/)

          bal_record_type = "AC"
          doc_type = "CLTR"
          orig_code = "CC"
          doc_from_char = "C"
          doc_num_as_str = doc_num.to_s
          desc = "#{facility_initials}|#{prod.name}|#{date}"[0..39]
          tx_dollar_amt = od.actual_cost.truncate(2).to_s("F")

          puts("tx_dollar_amt = #{tx_dollar_amt}")

          ref_field_1 = od.order_id.to_s
          ref_field_2 = od.id.to_s

          # make the LedgerEntry to track this export
          tracking_row = LedgerEntry.new(
              batch_sequence_number: @batch_sequence_number,
              document_number: doc_num,
              exported_on: DateTime.now,
              journal_row: journal_row
          )
          tracking_row.kfs_status = "pending"
          tracking_row.save!


          # Comments indicate the corresponding fields specified in the
          # "General Ledger (GL) Credit Entry" and "General Ledger (GL) Debit Entry" sections
          # of the "Collector Batch Format" document
          [
            { :match => aan_match, :code => "D" },
            { :match => fan_match, :code => "C" },
          ].each { |data|
            entry = [

              # "Fiscal Year" - Changes on July 1st
              @fiscal_year.ljust(4),

              # "Chart of Accounts code"
              @chart_accounts_code.ljust(2),

              # "Account Number" - Account number to be credited or debited
              data[:match][:acct_num].ljust(7),

              # "Filler" - Blanks or spaces
              " " * 5,

              # "Object Code" - Object Code to be credited or debited
              data[:match][:obj_code].ljust(4),

              # "Filler" - Blanks or spaces
              " " * 3,

              # "Balance Type"
              bal_record_type.ljust(2),

              # "Filler" - Blanks or spaces
              " " * 4,

              # "Document Type"
              doc_type.ljust(4),

              # "Origin Code"
              orig_code.ljust(2),

              # "Document Number – 1st position"
              doc_from_char.ljust(1),

              # "Document Number – 2 thru 14"
              # An increasing sequential number beginning with zero.
              # Should be the same for each Debit(D) and Credit(C) entry.
              doc_num_as_str.rjust(13, "0"),

              # "Filler" - Blanks or spaces
              " " * 5,

              # "Description" - Transaction Description
              desc.ljust(40),

              # "Filler" - Blanks or spaces
              " " * 1,

              # "Transaction Dollar Amount"
              # Amount to be credited or debited, must include decimal point, for example 00000000000000114.00
              tx_dollar_amt.rjust(20, "0"),

              # "Debit/Credit code"
              # "C" for Credit, "D" for Debit
              data[:code].ljust(1),

              # "Transaction Date" - Format CCYY-MM-DD
              date.ljust(10),

              # "Organization Document Number"
              # "Usually FRS Reference 1 fields, as long as amount is not to be encumbered."
              ref_field_1.ljust(10),

              # "Filler" - Blanks or spaces
              " " * 10,

              # "Organization Reference ID"
              # "Usually FRS Reference 2 fields, as long as amount is not to be encumbered."
              ref_field_2.ljust(8),

              # "Filler" - Blanks or spaces
              " " * 31,
            ]
            records += 1
            doc_num += 1
            file_amt += Float(tx_dollar_amt)

            output << entry.join("") << "\n"
          }
      end

      trailer_record = generate_trailer_record(records, file_amt)

      output << trailer_record << "\n"

      return output
    end

    def generate_trailer_record(records, file_amt)
      # Generate the "Trailed Record"
      # see the "Trailer Record (One per file):" section of the "Collector Batch Format" document
      trailer_record_type = "TL"
      trailer_record = [

        # "Filler"
        " " * 25,

        # "Record Type" - alwasy "TL" for Trailer Record
        trailer_record_type.ljust(2),

        # "Fillter"
        " " * 19,

        # "Number of records in file"
        # Total Credit GL Entries plus Total Debit GL Entries (do not count header and trailer records)
        records.to_s.rjust(5, "0"),

        # "Fillter"
        " " * 41,

        # "File Amount"
        # Money format (2 decimal places) right aligned, leading zeroes, no commas
        # Total amount credited plus total amount debited. Cannot be zero.
        # Must include decimal point, for example 00000000000000114.00
        file_amt.truncate(2).to_s.rjust(20, "0"),
      ]
      return trailer_record.join("")
    end
  end
end
