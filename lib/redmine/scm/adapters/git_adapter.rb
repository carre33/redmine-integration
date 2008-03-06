# redMine - project management software
# Copyright (C) 2006-2007  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require 'redmine/scm/adapters/abstract_adapter'

module Redmine
  module Scm
    module Adapters    
      class GitAdapter < AbstractAdapter
      
        # Git executable name
        GIT_BIN = "git"
        

        #get the revision of a particuliar file
	def get_rev (rev,path)
cmd="cd #{target('')} && git show #{rev} #{path}" if rev!='latest'
cmd="cd #{target('')} && git log -1 master -- #{path}" if 
rev=='latest' or rev.nil?
rev=[]
 i=0
 puts "get_rev"
 puts cmd
    shellout(cmd) do |io|
          commit_files=[]
          params={:commit=>'',:author=>'',:date=>'',:message=>'',:file=>{:path=>'',:action=>''}}
         
          message=''
	io.each_line do |line|

	        i=0 if line=~/^commit/
		params[:commit]=line.chomp.gsub("commit ",'') if i==0
		
		params[:author]=line.chomp.gsub("Author: ",'') if i==1
		params[:date]=line.chomp.gsub("Date: ",'') if i==2
		params[:message]+= line.chomp.to_s if i==4 and line[0..0]!=':'
		params[:file][:action], params[:file][:path]= line.chomp.slice(/[ACDMRTUXB].*/).split(' ', 2) if i>=4 and line[0..0]==':'
		commit_files << {:action=>params[:file][:action],:path=>params[:file][:path]}  if i>=4 and line[0..0]==':'
		i+=1
		end	
		
		rev = Revision.new({:identifier => nil,
                                       :scmid => params[:commit],
                                       :author => params[:author],
                                       :time => Time.parse(params[:date]),
                                       :message => params[:message],
                                       :paths => commit_files
            				})
	end

	get_rev('latest',path) if i==0

          return nil if $? && $?.exitstatus != 0
          return rev
#         rescue Errno::ENOENT => e
#           raise CommandFailed
end


        def info
#           cmd = "#{GIT_BIN} -R #{target('')} root"
#           root_url = nil
#           shellout(cmd) do |io|
             root_url = target('')
#           end
          info = Info.new({:root_url => target(''),
                           :lastrev => revisions(root_url,nil,nil,nil).first
                         })
          info
        rescue Errno::ENOENT => e
          return nil
        end
        
        def entries(path=nil, identifier=nil)
          path ||= ''
          entries = Entries.new
          cmd = "cd #{target('')} && #{GIT_BIN} show HEAD:#{path}" if identifier.nil?
          cmd = "cd #{target('')} && #{GIT_BIN} show #{identifier}:#{path}" if identifier
	shellout(cmd)  do |io|
	 io.each_line do |line|
              e = line.chomp.split('\\')
	unless e.to_s.strip=='' or line[0..3]=='tree'
	name=e.first.split('/')[0]
              entries << Entry.new({:name => name,
                                    :path => (path.empty? ? name : "#{path}/#{name}"),
                                    :kind => ((e.first.include? '/') ? 'dir' : 'file'),
                                    :lastrev => get_rev(identifier,(path.empty? ? name : "#{path}/#{name}"))
                                    }) unless entries.detect{|entry| entry.name == name}
         end
	end
	end
          return nil if $? && $?.exitstatus != 0
          entries.sort_by_name
#         rescue Errno::ENOENT => e
#           raise CommandFailed
        end
  
        def entry(path=nil, identifier=nil)
          path ||= ''
          search_path = path.split('/')[0..-2].join('/')
          entry_name = path.split('/').last
          e = entries(search_path, identifier)
          e ? e.detect{|entry| entry.name == entry_name} : nil
        end
          
		def revisions(path, identifier_from, identifier_to, options={})
		revisions = Revisions.new
		cmd = "cd #{target('')} && #{GIT_BIN} whatchanged "
		cmd << " #{identifier_from}.. " if identifier_from
		cmd << " #{identifier_to} " if identifier_to
                #cmd << " HEAD " if !identifier_to
                puts "revisions"
                puts cmd
		shellout(cmd) do |io|
		files=[]
		params={:commit=>'',:author=>'',:date=>'',:message=>'',:file=>{:path=>'',:action=>''}}
		i=0
		message=''
		io.each_line do |line|
	
			if line=~/^commit/ and i>0
			revisions << Revision.new({:identifier => nil,
					:scmid => params[:commit],
					:author => params[:author],
					:time => Time.parse(params[:date]),
					:message => params[:message],
					:paths => files
						})
	
			files=[]	
			i=0
			params={:commit=>'',:author=>'',:date=>'',:message=>'',:file=>{:path=>'',:action=>''}}
			end
			params[:commit]=line.chomp.gsub("commit ",'') if i==0
			params[:author]=line.chomp.gsub("Author: ",'') if i==1
			params[:date]=line.chomp.gsub("Date: ",'') if i==2
			params[:message]+= line.chomp.to_s if i>=4 and line[0..0]!=':'
			params[:file][:action], params[:file][:path]= line.chomp.slice(/[ACDMRTUXB].*/).split(' ', 2) if i>=4 and line[0..0]==':'
			files << {:action=>params[:file][:action],:path=>params[:file][:path]}  if i>=4 and line[0..0]==':'
			i+=1
			end	
		end

          return nil if $? && $?.exitstatus != 0
           puts "RETURNING REVISIONS"
           revisions
        rescue Errno::ENOENT => e
          raise CommandFailed
	   end
        
        def diff(path, identifier_from, identifier_to=nil, type="inline")
          path ||= ''
          if identifier_to
            identifier_to = identifier_to 
          else
            identifier_to = nil
          end
          cmd = "cd #{target('')} && #{GIT_BIN}  diff   #{identifier_from}^!" if identifier_to.nil?
          cmd = "cd #{target('')} && #{GIT_BIN}  diff #{identifier_to}  #{identifier_from}" if !identifier_to.nil?
          cmd << " #{path}" unless path.empty?
          diff = []
          shellout(cmd) do |io|
            io.each_line do |line|
              diff << line
            end
          end
          return nil if $? && $?.exitstatus != 0
          DiffTableList.new diff, type
    
        rescue Errno::ENOENT => e
          raise CommandFailed
        end
        
        def cat(path, identifier=nil)
          cmd = "cd #{target('')} && #{GIT_BIN} show #{identifier}:#{path}"
          cat = nil
          shellout(cmd) do |io|
            io.binmode
            cat = io.read
          end
          return nil if $? && $?.exitstatus != 0
          cat
        rescue Errno::ENOENT => e
          raise CommandFailed
        end
      end
    end
  end

end

