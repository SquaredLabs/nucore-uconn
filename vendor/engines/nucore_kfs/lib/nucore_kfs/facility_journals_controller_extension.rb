module NucoreKfs
  module FacilityJournalsControllerExtension
    def after_success(journal)
      puts("NucoreKfs::FacilityJournalsControllerExtension | after_success hook called")
      UchTransactionsMailer.transaction_email(journal).deliver_now
    end
  end
end