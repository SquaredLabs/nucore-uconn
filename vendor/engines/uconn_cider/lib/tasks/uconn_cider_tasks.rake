# desc "Explaining what the task does"
# task :uconn_cider do
#   # Task goes here
# end

#Checks a log against the reservations in CIDER
task :nmrparse, [:file_path] => :environment do |t, args|
	records = []
	#parses records from text file
	File.open(args[:file_path], "r").each do |line|
		halved = line.split(" ", 2)	#first half contains netid, second half contains date and time
		
		netid = halved[0]
		
		#pulls out day + month
		reservation_info = halved[1].split(/\w\w\w\s\w\w\w\s+\S+\s/, 2)[1].split(/\s\S\s/)
		
		date = Date.parse(halved[1].scan(/\w\w\w\s\w\w\w\s+\S+\s/)[0])
		
		reservation_start = reservation_info[0]
		reservation_end = reservation_info[1].scan(/\S\S\S\S\S/)[0]
		#puts reservation_start + " " + reservation_end
		records.append([netid, date, reservation_start, reservation_end])
	end
	
	#checks if there are matching reservations in CIDER
	records.each do |record|
		puts Reservation
			.where(reserve_start_at: records[2], reserve_end_at: records[3])
			.none?
	end
end
