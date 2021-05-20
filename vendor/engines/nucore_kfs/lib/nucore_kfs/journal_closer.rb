module NucoreKfs
  module JournalsCloserExtension
    def after_success
      puts("NucoreKfs::Journals::Closer | after_success hook called")
      UchTransactionsMailer.transaction_email(journal).deliver_now
    end
  end
end