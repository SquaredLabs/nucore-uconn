# frozen_string_literal: true

FactoryBot.define do
  factory :collector_transaction, class: NucoreKfs::CollectorTransaction do
    document_number { 1 }
    journal_row
    transaction_dollar_amount { 1.01 }

    initialize_with { new(journal_row, document_number) }
  end
end
