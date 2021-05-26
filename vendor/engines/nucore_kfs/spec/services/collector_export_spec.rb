require "rails_helper"
require_relative "../kfs_spec_helper.rb"

RSpec.describe NucoreKfs::CollectorExport, type: :service do
  let(:user) { FactoryBot.create(:user) }
  let(:facility) { FactoryBot.create(:setup_kfs_facility) }
  let(:kfs_account) { FactoryBot.create(:nufs_account, :with_account_owner, owner: user, account_number: "KFS-7777777-4444") }
  let(:uch_account) { FactoryBot.create(:nufs_account, :with_account_owner, owner: user, account_number: "UCH-7777777-4444") }

  context "in open journal with KFS account" do
    let(:exporter) { described_class.new(1) }
    let(:journal) { FactoryBot.create(:kfs_journal, facility: facility) }
    let(:order_detail) { place_and_complete_kfs_item_order(user, facility, kfs_account, true) }
    let(:journal_rows) {
      journal.create_journal_rows!([order_detail])
      journal.journal_rows
    }


    context "collector" do
      let(:transaction1) { FactoryBot.build(:collector_transaction, journal_row: journal_rows[0]) }

      # This example comes from a set of orders we found that led to a bug when summing them up as floats
      # If someone has a better idea on how to test for this regression, I welcome suggestions!
      let(:order_values_with_float_sum_bug) {
        [
          120.0,
          139.0,
          180.0,
          58.0,
          116.0,
          180.0,
          1112.0,
          464.0,
          960.0,
          30.0,
          116.0,
          240.0,
          158.67,
          116.0,
          120.0,
          120.0,
          348.0,
          720.0,
          180.0,
          158.67,
          116.0,
          120.0,
          120.0,
          232.0,
          240.0,
          1112.0,
          232.0,
          480.0,
          60.0,
          60.0,
          1668.0,
          696.0,
          1440.0,
          116.0,
          120.0,
          420.0,
          58.0,
          60.0,
          58.0,
          60.0,
          120.0,
          660.0,
          116.0,
          120.0,
          142.0,
          960.0,
          232.0,
          480.0,
          174.0,
          360.0,
          278.0,
          240.0,
          406.0,
          420.0,
          232.0,
          240.0,
          240.0,
          58.0,
          120.0,
          40.0,
          50.0,
          49.5,
          190.01,
          60.0,
          40.0,
          40.0,
          60.0,
          40.0,
          130.01,
          50.0,
          80.0,
          190.01,
          160.01,
          140.01,
          210.01,
          230.01,
          190.01,
          130.01,
          50.0,
          70.0
        ]
      }

      it "handles invalid journal rows" do
        journal_row = double
        allow(journal_row).to receive(:order_detail).and_return(nil)
        
        expect{exporter.create_collector_transactions_from_journal_rows(journal_rows)}.to_not raise_error
      end

      it "can build transactions from multiple journal rows" do
        expect(exporter.create_collector_transactions_from_journal_rows(journal_rows)).to_not be_nil
      end

      it "has correct number of transactions" do
        transactions = exporter.create_collector_transactions_from_journal_rows(journal_rows)

        expect(transactions.count()).to eq(1)
      end

      it "can export journal" do
        expect(exporter.generate_export_file_new(journal_rows)).to_not be_nil
      end

      it "sums up the file amount correctly" do
        transactions = order_values_with_float_sum_bug.map { |x| FactoryBot.build(
            :collector_transaction,
            journal_row: journal_rows[0],
            transaction_dollar_amount: Money.from_amount(x, "USD")
          )
        }
        transaction_entries = exporter.create_general_ledger_entries_from_transactions(transactions)
        file_amt = transaction_entries[:file_amt]
        expect(file_amt.to_s).to eq("41803.86")
      end
    end

    context "exported collector" do

      it "has correct header format" do
        header = exporter.generate_export_header()

        expect(header.lines.count).to eq(1)
        expect(header.size).to eq(172)
        expect(header[10..14].blank?).to be true
        expect(header[170..171].blank?).to be true
      end

      it "has the default email in the header when none is specified" do
        header = exporter.generate_export_header()
        expect(header.include? "joseph.oshea@uconn.edu").to be true
      end

      it "has the default name in the header when none is specified" do
        header = exporter.generate_export_header()
        expect(header.include? "Joseph OShea").to be true
      end

      context "with an email and name provided" do
        let(:email) { "foo@bar.com" }
        let(:name) { "Mary Brown" }
        let(:exporter) { described_class.new(1, email, name) }

        it "has the specified email in the header" do
          header = exporter.generate_export_header()
          expect(header.include? email).to be true
        end

        it "has the specified name in the header" do
          header = exporter.generate_export_header()
          expect(header.include? name).to be true
        end
      end

      it "has correct number of general ledger entries" do
        transactions = exporter.create_collector_transactions_from_journal_rows(journal_rows)
        transaction_entries = exporter.create_general_ledger_entries_from_transactions(transactions)

        expect(transaction_entries[:records]).to eq(transactions.length() * 2)
      end
  
      it "has correct general ledger entry format for each transaction" do
        transactions = exporter.create_collector_transactions_from_journal_rows(journal_rows)
        transactions.each do |transaction|
          row = transaction.create_credit_row_string()

          expect(row.lines.count).to eq(1)
          expect(row.size).to eq(187)

          expect(row[13..17].blank?).to be true
          expect(row[22..24].blank?).to be true
          expect(row[27..30].blank?).to be true
          expect(row[51..54].blank?).to be true
          expect(row[91].blank?).to be true
          expect(row[132..140].blank?).to be true
          expect(row[157..187].blank?).to be true
        end
      end

      it "has valid trailer fields" do
        transactions = exporter.create_collector_transactions_from_journal_rows(journal_rows)
        transaction_entries = exporter.create_general_ledger_entries_from_transactions(transactions)

        expect(transaction_entries[:records]).to be > 0
        expect(transaction_entries[:file_amt]).to be > 0
      end
  
      it "has correct trailer format" do
        records = 2
        file_amt = Money.from_amount(200, "USD")
        trailer_record = exporter.generate_trailer_record(records, file_amt)

        expect(trailer_record.lines.count).to eq(1)
        expect(trailer_record.size).to eq(112)

        expect(trailer_record[0..24].blank?).to be true
        expect(trailer_record[27..45].blank?).to be true
        expect(trailer_record[51..91].blank?).to be true
      end

      it "has correct trailer amounts" do
      end
    end
  end

  context "in open journal with UCH account" do
    let(:exporter) { described_class.new(1) }
    let(:journal) { FactoryBot.create(:kfs_journal, facility: facility) }
    let(:order_detail) { place_and_complete_kfs_item_order(user, facility, uch_account, true) }
    let(:journal_rows) {
      journal.create_journal_rows!([order_detail])
      journal.journal_rows
    }

    context "collector" do

      it "handles invalid journal rows" do
        journal_row = double
        allow(journal_row).to receive(:order_detail).and_return(nil)
        
        expect{exporter.create_collector_transactions_from_journal_rows(journal_rows)}.to_not raise_error
      end

      it "can build transactions from multiple journal rows" do
        expect(exporter.create_collector_transactions_from_journal_rows(journal_rows)).to_not be_nil
      end

      it "has correct number of transactions" do
        transactions = exporter.create_collector_transactions_from_journal_rows(journal_rows)

        expect(transactions.length()).to eq(1)
      end

      it "can export journal" do
        expect(exporter.generate_export_file_new(journal_rows)).to_not be_nil
      end
    end

    context "exported collector" do

      it "has correct header format" do
        header = exporter.generate_export_header()

        expect(header.lines.count).to eq(1)
        expect(header.size).to eq(172)
        expect(header[10..14].blank?).to be true
        expect(header[170..171].blank?).to be true
      end

      it "has correct number of general ledger entries" do
        transactions = exporter.create_collector_transactions_from_journal_rows(journal_rows)
        transaction_entries = exporter.create_general_ledger_entries_from_transactions(transactions)

        expect(transaction_entries[:records]).to eq(transactions.length() * 2)
      end
  
      it "has correct general ledger entry format for each transaction" do
        transactions = exporter.create_collector_transactions_from_journal_rows(journal_rows)
        transactions.each do |transaction|
          row = transaction.create_credit_row_string()

          expect(row.lines.count).to eq(1)
          expect(row.size).to eq(187)

          expect(row[13..17].blank?).to be true
          expect(row[22..24].blank?).to be true
          expect(row[27..30].blank?).to be true
          expect(row[51..54].blank?).to be true
          expect(row[91].blank?).to be true
          expect(row[132..140].blank?).to be true
          expect(row[157..187].blank?).to be true
        end
      end

      it "has valid trailer fields" do
        transactions = exporter.create_collector_transactions_from_journal_rows(journal_rows)
        transaction_entries = exporter.create_general_ledger_entries_from_transactions(transactions)

        expect(transaction_entries[:records]).to be > 0
        expect(transaction_entries[:file_amt]).to be > 0
      end
  
      it "has correct trailer format" do
        records = 2
        file_amt = Money.from_amount(200, "USD")
        trailer_record = exporter.generate_trailer_record(records, file_amt)

        expect(trailer_record.lines.count).to eq(1)
        expect(trailer_record.size).to eq(112)

        expect(trailer_record[0..24].blank?).to be true
        expect(trailer_record[27..45].blank?).to be true
        expect(trailer_record[51..91].blank?).to be true
      end

      it "has correct trailer amounts" do
      end
    end
  end
end
