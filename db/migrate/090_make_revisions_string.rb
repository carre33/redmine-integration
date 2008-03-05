class MakeRevisionsString < ActiveRecord::Migration
  def self.up
	change_column :changes, :from_revision, :string
        change_column :changesets, :revision, :string
  end

  def self.down
        change_column :changes, :from_revision, :integer
        change_column :changesets, :revision, :integer
   end
end
