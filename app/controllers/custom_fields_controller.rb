#-- encoding: UTF-8

#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2017 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
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
#
# See doc/COPYRIGHT.rdoc for more details.
#++

class CustomFieldsController < ApplicationController
  layout 'admin'

  before_action :require_admin
  before_action :find_custom_field, only: %i(edit update destroy move delete_option)
  before_action :get_custom_field_params, only: %i(create update)

  def index
    # loading wp cfs exclicity to allow for eager loading
    @custom_fields_by_type = CustomField.all.where.not(type: 'WorkPackageCustomField').group_by { |f| f.class.name }
    @custom_fields_by_type['WorkPackageCustomField'] = WorkPackageCustomField.includes(:types).all

    @tab = params[:tab] || 'WorkPackageCustomField'
  end

  def new
    @custom_field = careful_new_custom_field permitted_params.custom_field_type
  end

  def create
    @custom_field = careful_new_custom_field permitted_params.custom_field_type, @custom_field_params

    set_custom_options!

    if @custom_field.save
      flash[:notice] = l(:notice_successful_create)
      call_hook(:controller_custom_fields_new_after_save, custom_field: @custom_field)
      redirect_to custom_fields_path(tab: @custom_field.class.name)
    else
      render action: 'new'
    end
  end

  def edit; end

  def update
    ok = @custom_field.update_attributes(@custom_field_params)

    if ok
      set_custom_options!
      ok = @custom_field.save
    end

    if ok
      flash[:notice] = t(:notice_successful_update)
      call_hook(:controller_custom_fields_edit_after_save, custom_field: @custom_field)
      redirect_back_or_default edit_custom_field_path(id: @custom_field.id)
    else
      render action: 'edit'
    end
  end

  def destroy
    begin
      @custom_field.destroy
    rescue
      flash[:error] = l(:error_can_not_delete_custom_field)
    end
    redirect_to custom_fields_path(tab: @custom_field.class.name)
  end

  def delete_option
    custom_option = CustomOption.find params[:option_id]

    if custom_option
      num_deleted = delete_custom_values! custom_option
      custom_option.destroy!

      flash[:notice] = I18n.t(
        :notice_custom_options_deleted, option_value: custom_option.value, num_deleted: num_deleted
      )
    else
      flash[:error] = I18n.t(:error_custom_option_not_found)
    end

    redirect_to edit_custom_field_path(id: @custom_field.id)
  end

  private

  def get_custom_field_params
    @custom_field_params = permitted_params.custom_field

    if !EnterpriseToken.allows_to?(:multiselect_custom_fields)
      @custom_field_params.delete :multi_value
    end
  end

  def delete_custom_values!(custom_option)
    CustomValue
      .where(custom_field_id: custom_option.custom_field_id, value: custom_option.id)
      .delete_all
  end

  def set_custom_options!
    if @custom_field.list?
      custom_options = Hash(params.permit!.to_h.dig("custom_field", "custom_options"))
      custom_options.each_with_index do |(id, attr), i|
        set_custom_option! id, attr, i
      end
    end
  end

  def set_custom_option!(id, attr, i)
    attr = attr.slice(:value, :default_value)

    if @custom_field.new_record? || !CustomOption.exists?(id)
      build_custom_option! attr, i
    else
      update_custom_option! id, attr, i
    end
  end

  def build_custom_option!(attr, i)
    @custom_field.custom_options.build(
      value: attr[:value], position: i + 1, default_value: attr[:default_value]
    )
  end

  def update_custom_option!(id, attr, i)
    @custom_field.custom_options.select { |co| co.id == id.to_i }.each do |custom_option|
      custom_option.value = attr[:value] if custom_option.value != attr[:value]
      custom_option.default_value = attr[:default_value].present?
      custom_option.position = i + 1
      custom_option.save!
    end
  end

  def careful_new_custom_field(type, params = {})
    cf = begin
      if type.to_s =~ /.+CustomField\z/
        klass = type.to_s.constantize
        klass.new(params) if klass.ancestors.include? CustomField
      end
    rescue NameError => e
      Rails.logger.error "#{e.message}:\n#{e.backtrace.join("\n")}"
      nil
    end
    redirect_to custom_fields_path unless cf
    cf
  end

  def find_custom_field
    @custom_field = CustomField.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  protected

  def default_breadcrumb
    if action_name == 'index'
      t('label_custom_field_plural')
    else
      ActionController::Base.helpers.link_to(t('label_custom_field_plural'), custom_fields_path)
    end
  end

  def show_local_breadcrumb
    true
  end
end
