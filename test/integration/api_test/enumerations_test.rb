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

require File.expand_path('../../../test_helper', __FILE__)

class ApiTest::EnumerationsTest < ActionController::IntegrationTest
  fixtures :enumerations

  def setup
    Setting.rest_api_enabled = '1'
  end

  context "/enumerations/issue_priorities" do
    context "GET" do

      should "return priorities" do
        get '/enumerations/issue_priorities.xml'

        assert_response :success
        assert_equal 'application/xml', response.content_type
        assert_select 'issue_priorities[type=array]' do
          assert_select 'issue_priority' do
            assert_select 'id', :text => '6'
            assert_select 'name', :text => 'High'
          end
        end
      end
    end
  end
end
