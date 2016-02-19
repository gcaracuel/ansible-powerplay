# -*- coding: utf-8 -*-
require 'ansible-powerplay'

module Powerplay
  module Play
    DEFOUT = "&1" # default non-tmux output

    def self.clopts
      @cliots ||= DSL::_global[:options]
    end

    module Tmux
      # Get a list of the ptys
      # Note that this code is a bit innefficient, but will only be
      # executed once in the loop.
      def self.pane_ptys
        @window = if Play::clopts.nil? or Play::clopts[:tmux] == 0
                    ''
                  else
                    " -t #{Play::clopts[:tmux]} "
                  end
        @ptys ||= if Play::clopts.nil? or Play::clopts[:tmux]
                    %x[tmux list-panes #{@window} -F '\#{pane_tty},']
                      .inspect
                      .chop
                      .split(",")
                      .map{ |s| s.strip.sub(/\\n|\"/, '') }
                      .reject{ |pty| pty == %x(tty).chop }
                  else
                    [Play::DEFOUT]
                  end
      end
    end

    module Ansible
      PLAYBOOK = "ansible-playbook"
      OPTS = ""

      def self.playbooks
        play = Play::clopts[:play].to_sym
        if play == :all
          DSL::_global[:playbooks].each do |pplay, group|
            yield pplay, group
          end
        else
          yield play, DSL::_global[:playbooks][play]
        end
      end
      
      # groups are serial
      def self.groups(playbook)
        grp = Play::clopts[:group].to_sym
        playbook.groups.each do |group|
          yield group if grp == :all or grp == group.type  
        end
      end

      def self.power_run
        buch = Play::clopts[:book].to_sym
        dryrun = Play::clopts[:dryrun]
        congroups = Play::clopts[:congroups]
        playbooks do |pname, playbook|
          thrgroups = []
          puts "PLAYBOOK #{pname} (group=#{Play::clopts[:group]}) -->"
          groups playbook do |group|
            tg = nil
            thrgroups << (tg = Thread.new {
                            puts "    GROUP #{group.type} (book=#{buch}, cg=#{congroups}) -->"
                            thrbooks = []
                            errors = []
                            group.books.zip(Tmux.pane_ptys) do |book, tty|
                              tty ||= Tmux.pane_ptys.last
                              if buch == :all or book.type == buch
                                puts "        BOOK #{book.type}"
                                inv = if book.config.member? :inventory 
                                        "-i #{book.config[:inventory].first}" 
                                      else
                                        ''
                                      end
                                apcmd = %|#{PLAYBOOK} #{OPTS} #{inv} #{book.config[:playbook_directory].first}/#{book.yaml} --extra-vars "#{book.aparams}" >#{tty}|
                                thrbooks << Thread.new {
                                  std, status = Open3.capture2e apcmd
                                  errors << [book.yaml, apcmd, std] unless status.success?
                                } unless dryrun
                              end
                            end
                            thrbooks.each{ |t| t.join }
                            unless errors.empty?
                              errors.each do |yaml, cmd, txt|
                                puts '=' * 30
                                puts ('*' * 10) + ' ' + yaml
                                puts txt
                                puts '-' * 30
                                puts cmd
                              end
                              exit 10
                            end
                          })
            # Always wait here unless we're concurrent
            thrgroups.join unless congroups
          end
          thrgroups.each{ |t| t.join }
        end
      end
    end
  end
end
