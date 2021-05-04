class AddKfsUploadFlagToJournals < ActiveRecord::Migration[5.2]
  def change
    add_column :journals, :kfs_upload_generated, :boolean, null: false, default: false
  end
end
