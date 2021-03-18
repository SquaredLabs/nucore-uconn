# desc "Explaining what the task does"
# task :nucore_kfs do
#   # Task goes here
# end

desc "generate export file(s) for KFS collector for open journals"
task :kfs_collector_export_cron, [:export_dir] => :environment do |_t, args|
  export_dir = args.export_dir
  puts("Exporting to #{export_dir}")

  kfs_bot = User.find_or_create_by(
    username: NucoreKfs::KFS_BOT_ACCOUNT_USERNAME,
    email: NucoreKfs::KFS_BOT_ACCOUNT_EMAIL,
    first_name: "KFS",
    last_name: "Bot"
  )

  open_journals = Journal.where(is_successful: nil, kfs_upload_generated: false)

  # we must track the batch sequence number to tell KFS
  batch_sequence_number = 1
  open_journals.each do |journal|

    # builds rows for passing to CollectorExport. This could use some refactoring
    rows_to_export = journal.journal_rows

    # Get the director for the facility so we can set them as the receipient of the KFS Collector upload confirmation email
    facility_director = journal.facility.user_roles.where(role: 'Facility Director').first.user

    # Generate the file and write it
    exporter = NucoreKfs::CollectorExport.new(
      batch_sequence_number,
      facility_director.email,
      facility_director.name
    )
    export_content = exporter.generate_export_file_new(rows_to_export)

    file_name = "journal-#{journal.id}.data"
    export_file = File.join(export_dir, file_name);
    File.open(export_file, "w") { |file| file.write export_content }

    puts("Exported a Journal to #{export_file}")

    batch_sequence_number += 1
    journal.kfs_upload_generated = true
    journal.reference = file_name
    journal.updated_by = kfs_bot.id
    journal.save!

    # We can only do a max of 9 files per day. This is a constraint of the KFS Collector
    # system. We simply stop after 9. The rest will be picked up on the next day this cron
    # job runs
    MAX_BATCHES_PER_DAY = 9
    if (batch_sequence_number > MAX_BATCHES_PER_DAY)
      puts("Maximum batch sequence number of #{MAX_BATCHES_PER_DAY} reached for the day. Stopping.")
      break
    end

    # TODO: how do we get files moved to the SFTP folder? Should it be managed
    # by rails or should it be a separate cron script?
  end
end

desc "dry run - test generate an export file for the KFS Collector"
task :kfs_collector_export_dry_run, [:export_file_path] => :environment do |_t, args|
  export_file = args.export_file_path
  puts("Exporting to #{export_file}")

  open_journals = Journal.where(is_successful: nil)

  rows_to_export = []

  open_journals.each do |journal|
    journal.journal_rows.each do |journal_row|
      od = journal_row.order_detail
      next unless journal_row.order_detail
      prod = journal_row.order_detail.product
      aan_out = od.account.account_number
      fan_out = prod.facility_account.account_number

      rows_to_export.push(journal_row)
    end
  end

  exporter = NucoreKfs::CollectorExport.new(1)
  export_content = exporter.generate_export_file_new(rows_to_export)

  File.open(export_file, "w") { |file| file.write export_content }
end


desc "Generate an export file for the KFS Collector"
task :kfs_collector_export, [:export_file_path] => :environment do |_t, args|
  export_file = args.export_file_path
  puts("Exporting to #{export_file}")

  open_journals = Journal.where(is_successful: nil)

  rows_to_export = []

  open_journals.each do |journal|
    journal.journal_rows.each do |journal_row|
      od = journal_row.order_detail
      next unless journal_row.order_detail
      prod = journal_row.order_detail.product
      aan_out = od.account.account_number
      fan_out = prod.facility_account.account_number

      aan_match = aan_out.match(/^KFS-(?<acct_num>\d{0,7})-(?<obj_code>\d{4})$/)
      fan_match = fan_out.match(/^KFS-(?<acct_num>\d{0,7})-(?<obj_code>\d{4})$/)

      if !aan_match
        # logger.info("for id #{od.id}: order account not a kfs account: #{aan_out}")
        puts("for id #{od.id}: order account not a kfs account: #{aan_out}")
      elsif !fan_match
        # logger.info("for id #{od.id}: recharge account not a kfs account: #{fan_out}")
        puts("for id #{od.id}: recharge account not a kfs account: #{fan_out}")
      elsif LedgerEntry.where(journal_row_id: journal_row.id).empty?
        rows_to_export.push(journal_row)
      else
        # logger.info("LedgerEntry already exists for journal_row_id = #{journal_row.id}")
        puts("LedgerEntry already exists for journal_row_id = #{journal_row.id}")
      end
    end
  end

  exporter = NucoreKfs::CollectorExport.new(1)
  export_content = exporter.generate_export_file_new(rows_to_export)
  # export_content = exporter.generate_export_file(rows_to_export)

  File.open(export_file, "w") { |file| file.write export_content }

end

desc "Perform ETL of KFS ChartOfAccounts SOAP API"
task :kfs_chart_of_accounts => :environment do
  subfunds = [
    'OPAUX',
    'OPOTF',
    'OPOTP',
    'OPTUI',
    'RFNDA',
    'RFNDO',
    'RSFAD',
    'RSNSF',
    'RSNSP',
    'RSTSP',
    'UNRSF',
    'UNRSP',
  ]
  api = NucoreKfs::ChartOfAccounts.new

  for subfund in subfunds
    api.upsert_accounts_for_subfund(subfund)
  end

end


desc "Load UCH Banner Index accounts"
task :uch_load_banner_index, [:csv_file_path] => :environment do |_t, args|
  csv_file_path = args.csv_file_path
  loader = NucoreKfs::BannerUpserter.new
  loader.parse_file(csv_file_path)
end
