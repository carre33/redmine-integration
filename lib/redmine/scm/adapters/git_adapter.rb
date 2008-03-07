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

        # Convert an identifier to a git revision
        def id_to_rev(identifier)
          if identifier.nil?
            return nil
          end
          
          cmd = "cd #{target('')} && #{GIT_BIN} log --reverse --raw "
          cmd << "--skip="
          cmd << ((identifier - 1).to_s)
          answer = nil

          shellout(cmd) do |io|
            
            io.each_line do |line|
              if answer.nil? && line =~ /^commit ([0-9a-f]{40})$/
                answer = $1
              else
                next
              end
            end
          end

          return answer
        end

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
            files=[]
            changeset = {}
            parsing_descr = 0  #0: not parsing desc or files, 1: parsing desc, 2: parsing files
            line_feeds = 0

            io.each_line do |line|
              if line =~ /^commit ([0-9a-f]{40})$/
                key = "commit"
                value = $1
                if (parsing_descr == 1 || parsing_descr == 2)
                  parsing_descr = 0
                  rev = Revision.new({:identifier => nil,
                                             :scmid => changeset[:commit],
                                             :author => changeset[:author],
                                             :time => Time.parse(changeset[:date]),
                                             :message => changeset[:description],
                                             :paths => files
                                            })
                  changeset = {}
                  files = []
                end
                changeset[:commit] = $1
              elsif (parsing_descr == 0) && line =~ /^(\w+):\s*(.*)$/
                key = $1
                value = $2
                if key == "Author"
                  changeset[:author] = value
                elsif key == "Date"
                  changeset[:date] = value
                end
              elsif (parsing_descr == 0) && line.chomp.to_s == ""
                parsing_descr = 1
                changeset[:description] = ""
              elsif (parsing_descr == 1 || parsing_descr == 2) && line =~ /^:\d+\s+\d+\s+[0-9a-f.]+\s+[0-9a-f.]+\s+(\w)\s+(.+)$/
                parsing_descr = 2
                fileaction = $1
                filepath = $2
                files << {:action => fileaction, :path => filepath}
              elsif (parsing_descr == 1) && line.chomp.to_s == ""
                parsing_descr = 2
              elsif (parsing_descr == 1)
                changeset[:description] << line
              end
            end	
            rev = Revision.new({:identifier => nil,
                                       :scmid => changeset[:commit],
                                       :author => changeset[:author],
                                       :time => Time.parse(changeset[:date]),
                                       :message => changeset[:description],
                                       :paths => files
                                      })

          end

          get_rev('latest',path) if rev == []

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
          puts " ENTRIES "
          print path
          puts ""
          print identifier
          puts ""
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
          cmd = "cd #{target('')} && #{GIT_BIN} log --raw "
          cmd << " #{identifier_from}.. " if identifier_from
          cmd << " #{identifier_to} " if identifier_to
          #cmd << " HEAD " if !identifier_to
          puts "revisions"
          puts cmd
          shellout(cmd) do |io|
            files=[]
            changeset = {}
            parsing_descr = 0  #0: not parsing desc or files, 1: parsing desc, 2: parsing files
            line_feeds = 0
            revno = 1

            io.each_line do |line|
              if line =~ /^commit ([0-9a-f]{40})$/
                key = "commit"
                value = $1
                if (parsing_descr == 1 || parsing_descr == 2)
                  parsing_descr = 0
                  print revno
                  puts ""
                  puts changeset[:description]
                  revisions << Revision.new({:identifier => nil,
                                             :scmid => changeset[:commit],
                                             :author => changeset[:author],
                                             :time => Time.parse(changeset[:date]),
                                             :message => changeset[:description],
                                             :paths => files
                                            })
                  changeset = {}
                  files = []
                  revno = revno + 1
                end
                changeset[:commit] = $1
              elsif (parsing_descr == 0) && line =~ /^(\w+):\s*(.*)$/
                key = $1
                value = $2
                if key == "Author"
                  changeset[:author] = value
                elsif key == "Date"
                  changeset[:date] = value
                end
              elsif (parsing_descr == 0) && line.chomp.to_s == ""
                parsing_descr = 1
                changeset[:description] = ""
              elsif (parsing_descr == 1 || parsing_descr == 2) && line =~ /^:\d+\s+\d+\s+[0-9a-f.]+\s+[0-9a-f.]+\s+(\w)\s+(.+)$/
                parsing_descr = 2
                fileaction = $1
                filepath = $2
                files << {:action => fileaction, :path => filepath}
              elsif (parsing_descr == 1) && line.chomp.to_s == ""
                parsing_descr = 2
              elsif (parsing_descr == 1)
                changeset[:description] << line[4..-1]
              end
            end	
            print revno
            puts ""
            puts changeset[:description]

            revisions << Revision.new({:identifier => nil,
                                       :scmid => changeset[:commit],
                                       :author => changeset[:author],
                                       :time => Time.parse(changeset[:date]),
                                       :message => changeset[:description],
                                       :paths => files
                                      })

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

          puts "calling diff"
          print identifier_from
          puts ""
          print identifier_to
          puts ""
          puts "running diff"

          identifier_from = id_to_rev(identifier_from)
          identifier_to = id_to_rev(identifier_to)
          
          cmd = "cd #{target('')} && #{GIT_BIN}  diff   #{identifier_from}^!" if identifier_to.nil?
          cmd = "cd #{target('')} && #{GIT_BIN}  diff #{identifier_to}  #{identifier_from}" if !identifier_to.nil?
          cmd << " -- #{path}" unless path.empty?
          puts cmd
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
          identifier = id_to_rev(identifier)
          puts " ** CAT "
          print identifier
          puts ""
          if identifier.nil?
            identifier = 'HEAD'
          end
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

