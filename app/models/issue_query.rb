# Redmine - project management software
# Copyright (C) 2006-2013  Jean-Philippe Lang
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

class IssueQuery < Query

  self.queried_class = Issue

  self.available_columns = [
    QueryColumn.new(:project, :sortable => "#{Project.table_name}.name", :groupable => true),
    QueryColumn.new(:tracker, :sortable => "#{Tracker.table_name}.position", :groupable => true),
    QueryColumn.new(:parent, :sortable => ["#{Issue.table_name}.root_id", "#{Issue.table_name}.lft ASC"], :default_order => 'desc', :caption => :field_parent_issue),
    QueryColumn.new(:status, :sortable => "#{IssueStatus.table_name}.position", :groupable => true),
    QueryColumn.new(:priority, :sortable => "#{IssuePriority.table_name}.position", :default_order => 'desc', :groupable => true),
    QueryColumn.new(:subject, :sortable => "#{Issue.table_name}.subject"),
    QueryColumn.new(:author, :sortable => lambda {User.fields_for_order_statement("authors")}, :groupable => true),
    QueryColumn.new(:assigned_to, :sortable => lambda {User.fields_for_order_statement}, :groupable => true),
    QueryColumn.new(:updated_on, :sortable => "#{Issue.table_name}.updated_on", :default_order => 'desc'),
    QueryColumn.new(:category, :sortable => "#{IssueCategory.table_name}.name", :groupable => true),
    QueryColumn.new(:fixed_version, :sortable => lambda {Version.fields_for_order_statement}, :groupable => true),
    QueryColumn.new(:start_date, :sortable => "#{Issue.table_name}.start_date"),
    QueryColumn.new(:due_date, :sortable => "#{Issue.table_name}.due_date"),
    QueryColumn.new(:estimated_hours, :sortable => "#{Issue.table_name}.estimated_hours"),
    QueryColumn.new(:done_ratio, :sortable => "#{Issue.table_name}.done_ratio", :groupable => true),
    QueryColumn.new(:created_on, :sortable => "#{Issue.table_name}.created_on", :default_order => 'desc'),
    QueryColumn.new(:relations, :caption => :label_related_issues),
    QueryColumn.new(:description, :inline => false)
  ]

  scope :visible, lambda {|*args|
    user = args.shift || User.current
    base = Project.allowed_to_condition(user, :view_issues, *args)
    user_id = user.logged? ? user.id : 0

    includes(:project).where("(#{table_name}.project_id IS NULL OR (#{base})) AND (#{table_name}.is_public = ? OR #{table_name}.user_id = ?)", true, user_id)
  }

  def initialize(attributes=nil, *args)
    super attributes
    self.filters ||= { 'status_id' => {:operator => "o", :values => [""]} }
  end

  # Returns true if the query is visible to +user+ or the current user.
  def visible?(user=User.current)
    (project.nil? || user.allowed_to?(:view_issues, project)) && (self.is_public? || self.user_id == user.id)
  end

  def available_filters
    return @available_filters if @available_filters
    @available_filters = {
      "status_id" => {
        :type => :list_status, :order => 0,
        :values => IssueStatus.sorted.all.collect{|s| [s.name, s.id.to_s] }
       },
      "tracker_id" => {
        :type => :list, :order => 2, :values => trackers.collect{|s| [s.name, s.id.to_s] }
       },
      "priority_id" => {
        :type => :list, :order => 3, :values => IssuePriority.all.collect{|s| [s.name, s.id.to_s] }
       },
      "subject" => { :type => :text, :order => 8 },
      "created_on" => { :type => :date_past, :order => 9 },
      "updated_on" => { :type => :date_past, :order => 10 },
      "start_date" => { :type => :date, :order => 11 },
      "due_date" => { :type => :date, :order => 12 },
      "estimated_hours" => { :type => :float, :order => 13 },
      "done_ratio" =>  { :type => :integer, :order => 14 }
    }
    IssueRelation::TYPES.each do |relation_type, options|
      @available_filters[relation_type] = {
        :type => :relation, :order => @available_filters.size + 100,
        :label => options[:name]
      }
    end
    principals = []
    if project
      principals += project.principals.sort
      unless project.leaf?
        subprojects = project.descendants.visible.all
        if subprojects.any?
          @available_filters["subproject_id"] = {
            :type => :list_subprojects, :order => 13,
            :values => subprojects.collect{|s| [s.name, s.id.to_s] }
          }
          principals += Principal.member_of(subprojects)
        end
      end
    else
      if all_projects.any?
        # members of visible projects
        principals += Principal.member_of(all_projects)
        # project filter
        project_values = []
        if User.current.logged? && User.current.memberships.any?
          project_values << ["<< #{l(:label_my_projects).downcase} >>", "mine"]
        end
        project_values += all_projects_values
        @available_filters["project_id"] = {
          :type => :list, :order => 1, :values => project_values
        } unless project_values.empty?
      end
    end
    principals.uniq!
    principals.sort!
    users = principals.select {|p| p.is_a?(User)}

    assigned_to_values = []
    assigned_to_values << ["<< #{l(:label_me)} >>", "me"] if User.current.logged?
    assigned_to_values += (Setting.issue_group_assignment? ?
                              principals : users).collect{|s| [s.name, s.id.to_s] }
    @available_filters["assigned_to_id"] = {
      :type => :list_optional, :order => 4, :values => assigned_to_values
    } unless assigned_to_values.empty?

    author_values = []
    author_values << ["<< #{l(:label_me)} >>", "me"] if User.current.logged?
    author_values += users.collect{|s| [s.name, s.id.to_s] }
    @available_filters["author_id"] = {
      :type => :list, :order => 5, :values => author_values
    } unless author_values.empty?

    group_values = Group.all.collect {|g| [g.name, g.id.to_s] }
    @available_filters["member_of_group"] = {
      :type => :list_optional, :order => 6, :values => group_values
    } unless group_values.empty?

    role_values = Role.givable.collect {|r| [r.name, r.id.to_s] }
    @available_filters["assigned_to_role"] = {
      :type => :list_optional, :order => 7, :values => role_values
    } unless role_values.empty?

    if User.current.logged?
      @available_filters["watcher_id"] = {
        :type => :list, :order => 15, :values => [["<< #{l(:label_me)} >>", "me"]]
      }
    end

    if project
      # project specific filters
      categories = project.issue_categories.all
      unless categories.empty?
        @available_filters["category_id"] = {
          :type => :list_optional, :order => 6,
          :values => categories.collect{|s| [s.name, s.id.to_s] }
        }
      end
      versions = project.shared_versions.all
      unless versions.empty?
        @available_filters["fixed_version_id"] = {
          :type => :list_optional, :order => 7,
          :values => versions.sort.collect{|s| ["#{s.project.name} - #{s.name}", s.id.to_s] }
        }
      end
      add_custom_fields_filters(project.all_issue_custom_fields)
    else
      # global filters for cross project issue list
      system_shared_versions = Version.visible.find_all_by_sharing('system')
      unless system_shared_versions.empty?
        @available_filters["fixed_version_id"] = {
          :type => :list_optional, :order => 7,
          :values => system_shared_versions.sort.collect{|s|
                                       ["#{s.project.name} - #{s.name}", s.id.to_s]
                                     }
        }
      end
      add_custom_fields_filters(IssueCustomField.where(:is_filter => true, :is_for_all => true).all)
    end
    add_associations_custom_fields_filters :project, :author, :assigned_to, :fixed_version
    if User.current.allowed_to?(:set_issues_private, nil, :global => true) ||
      User.current.allowed_to?(:set_own_issues_private, nil, :global => true)
      @available_filters["is_private"] = {
        :type => :list, :order => 16,
        :values => [[l(:general_text_yes), "1"], [l(:general_text_no), "0"]]
      }
    end
    Tracker.disabled_core_fields(trackers).each {|field|
      @available_filters.delete field
    }
    @available_filters.each do |field, options|
      options[:name] ||= l(options[:label] || "field_#{field}".gsub(/_id$/, ''))
    end
    @available_filters
  end

  def available_columns
    return @available_columns if @available_columns
    @available_columns = self.class.available_columns.dup
    @available_columns += (project ?
                            project.all_issue_custom_fields :
                            IssueCustomField.all
                           ).collect {|cf| QueryCustomFieldColumn.new(cf) }

    if User.current.allowed_to?(:view_time_entries, project, :global => true)
      index = nil
      @available_columns.each_with_index {|column, i| index = i if column.name == :estimated_hours}
      index = (index ? index + 1 : -1)
      # insert the column after estimated_hours or at the end
      @available_columns.insert index, QueryColumn.new(:spent_hours,
        :sortable => "COALESCE((SELECT SUM(hours) FROM #{TimeEntry.table_name} WHERE #{TimeEntry.table_name}.issue_id = #{Issue.table_name}.id), 0)",
        :default_order => 'desc',
        :caption => :label_spent_time
      )
    end

    if User.current.allowed_to?(:set_issues_private, nil, :global => true) ||
      User.current.allowed_to?(:set_own_issues_private, nil, :global => true)
      @available_columns << QueryColumn.new(:is_private, :sortable => "#{Issue.table_name}.is_private")
    end

    disabled_fields = Tracker.disabled_core_fields(trackers).map {|field| field.sub(/_id$/, '')}
    @available_columns.reject! {|column|
      disabled_fields.include?(column.name.to_s)
    }

    @available_columns
  end

  def sortable_columns
    {'id' => "#{Issue.table_name}.id"}.merge(super)
  end

  def default_columns_names
    @default_columns_names ||= begin
      default_columns = Setting.issue_list_default_columns.map(&:to_sym)

      project.present? ? default_columns : [:project] | default_columns
    end
  end

  # Returns the issue count
  def issue_count
    Issue.visible.count(:include => [:status, :project], :conditions => statement)
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  # Returns the issue count by group or nil if query is not grouped
  def issue_count_by_group
    r = nil
    if grouped?
      begin
        # Rails3 will raise an (unexpected) RecordNotFound if there's only a nil group value
        r = Issue.visible.count(:joins => joins_for_order_statement(group_by_statement), :group => group_by_statement, :include => [:status, :project], :conditions => statement)
      rescue ActiveRecord::RecordNotFound
        r = {nil => issue_count}
      end
      c = group_by_column
      if c.is_a?(QueryCustomFieldColumn)
        r = r.keys.inject({}) {|h, k| h[c.custom_field.cast_value(k)] = r[k]; h}
      end
    end
    r
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  # Returns the issues
  # Valid options are :order, :offset, :limit, :include, :conditions
  def issues(options={})
    order_option = [group_by_sort_order, options[:order]].flatten.reject(&:blank?)

    issues = Issue.visible.where(options[:conditions]).all(
      :include => ([:status, :project] + (options[:include] || [])).uniq,
      :conditions => statement,
      :order => order_option,
      :joins => joins_for_order_statement(order_option.join(',')),
      :limit  => options[:limit],
      :offset => options[:offset]
    )

    if has_column?(:spent_hours)
      Issue.load_visible_spent_hours(issues)
    end
    if has_column?(:relations)
      Issue.load_visible_relations(issues)
    end
    issues
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  # Returns the issues ids
  def issue_ids(options={})
    order_option = [group_by_sort_order, options[:order]].flatten.reject(&:blank?)

    Issue.visible.scoped(:conditions => options[:conditions]).scoped(:include => ([:status, :project] + (options[:include] || [])).uniq,
                     :conditions => statement,
                     :order => order_option,
                     :joins => joins_for_order_statement(order_option.join(',')),
                     :limit  => options[:limit],
                     :offset => options[:offset]).find_ids
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  # Returns the journals
  # Valid options are :order, :offset, :limit
  def journals(options={})
    Journal.visible.all(
      :include => [:details, :user, {:issue => [:project, :author, :tracker, :status]}],
      :conditions => statement,
      :order => options[:order],
      :limit => options[:limit],
      :offset => options[:offset]
    )
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  # Returns the versions
  # Valid options are :conditions
  def versions(options={})
    Version.visible.where(options[:conditions]).all(
      :include => :project,
      :conditions => project_statement
    )
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  def sql_for_watcher_id_field(field, operator, value)
    db_table = Watcher.table_name
    "#{Issue.table_name}.id #{ operator == '=' ? 'IN' : 'NOT IN' } (SELECT #{db_table}.watchable_id FROM #{db_table} WHERE #{db_table}.watchable_type='Issue' AND " +
      sql_for_field(field, '=', value, db_table, 'user_id') + ')'
  end

  def sql_for_member_of_group_field(field, operator, value)
    if operator == '*' # Any group
      groups = Group.all
      operator = '=' # Override the operator since we want to find by assigned_to
    elsif operator == "!*"
      groups = Group.all
      operator = '!' # Override the operator since we want to find by assigned_to
    else
      groups = Group.find_all_by_id(value)
    end
    groups ||= []

    members_of_groups = groups.inject([]) {|user_ids, group|
      if group && group.user_ids.present?
        user_ids << group.user_ids
        user_ids << group.id
      end
      user_ids.flatten.uniq.compact
    }.sort.collect(&:to_s)

    '(' + sql_for_field("assigned_to_id", operator, members_of_groups, Issue.table_name, "assigned_to_id", false) + ')'
  end

  def sql_for_assigned_to_role_field(field, operator, value)
    case operator
    when "*", "!*" # Member / Not member
      sw = operator == "!*" ? 'NOT' : ''
      nl = operator == "!*" ? "#{Issue.table_name}.assigned_to_id IS NULL OR" : ''
      "(#{nl} #{Issue.table_name}.assigned_to_id #{sw} IN (SELECT DISTINCT #{Member.table_name}.user_id FROM #{Member.table_name}" +
        " WHERE #{Member.table_name}.project_id = #{Issue.table_name}.project_id))"
    when "=", "!"
      role_cond = value.any? ?
        "#{MemberRole.table_name}.role_id IN (" + value.collect{|val| "'#{connection.quote_string(val)}'"}.join(",") + ")" :
        "1=0"

      sw = operator == "!" ? 'NOT' : ''
      nl = operator == "!" ? "#{Issue.table_name}.assigned_to_id IS NULL OR" : ''
      "(#{nl} #{Issue.table_name}.assigned_to_id #{sw} IN (SELECT DISTINCT #{Member.table_name}.user_id FROM #{Member.table_name}, #{MemberRole.table_name}" +
        " WHERE #{Member.table_name}.project_id = #{Issue.table_name}.project_id AND #{Member.table_name}.id = #{MemberRole.table_name}.member_id AND #{role_cond}))"
    end
  end

  def sql_for_is_private_field(field, operator, value)
    op = (operator == "=" ? 'IN' : 'NOT IN')
    va = value.map {|v| v == '0' ? connection.quoted_false : connection.quoted_true}.uniq.join(',')

    "#{Issue.table_name}.is_private #{op} (#{va})"
  end

  def sql_for_relations(field, operator, value, options={})
    relation_options = IssueRelation::TYPES[field]
    return relation_options unless relation_options

    relation_type = field
    join_column, target_join_column = "issue_from_id", "issue_to_id"
    if relation_options[:reverse] || options[:reverse]
      relation_type = relation_options[:reverse] || relation_type
      join_column, target_join_column = target_join_column, join_column
    end

    sql = case operator
      when "*", "!*"
        op = (operator == "*" ? 'IN' : 'NOT IN')
        "#{Issue.table_name}.id #{op} (SELECT DISTINCT #{IssueRelation.table_name}.#{join_column} FROM #{IssueRelation.table_name} WHERE #{IssueRelation.table_name}.relation_type = '#{connection.quote_string(relation_type)}')"
      when "=", "!"
        op = (operator == "=" ? 'IN' : 'NOT IN')
        "#{Issue.table_name}.id #{op} (SELECT DISTINCT #{IssueRelation.table_name}.#{join_column} FROM #{IssueRelation.table_name} WHERE #{IssueRelation.table_name}.relation_type = '#{connection.quote_string(relation_type)}' AND #{IssueRelation.table_name}.#{target_join_column} = #{value.first.to_i})"
      when "=p", "=!p", "!p"
        op = (operator == "!p" ? 'NOT IN' : 'IN')
        comp = (operator == "=!p" ? '<>' : '=')
        "#{Issue.table_name}.id #{op} (SELECT DISTINCT #{IssueRelation.table_name}.#{join_column} FROM #{IssueRelation.table_name}, #{Issue.table_name} relissues WHERE #{IssueRelation.table_name}.relation_type = '#{connection.quote_string(relation_type)}' AND #{IssueRelation.table_name}.#{target_join_column} = relissues.id AND relissues.project_id #{comp} #{value.first.to_i})"
      end

    if relation_options[:sym] == field && !options[:reverse]
      sqls = [sql, sql_for_relations(field, operator, value, :reverse => true)]
      sqls.join(["!", "!*", "!p"].include?(operator) ? " AND " : " OR ")
    else
      sql
    end
  end

  IssueRelation::TYPES.keys.each do |relation_type|
    alias_method "sql_for_#{relation_type}_field".to_sym, :sql_for_relations
  end
end
