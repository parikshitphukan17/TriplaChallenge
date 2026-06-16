class Api::V1::PricingController < ApplicationController
  VALID_PERIODS = %w[Summer Autumn Winter Spring].freeze
  VALID_HOTELS = %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze
  VALID_ROOMS = %w[SingletonRoom BooleanTwin RestfulKing].freeze

  before_action :validate_params

  def index
    period = params[:period]
    hotel  = params[:hotel]
    room   = params[:room]

    begin
      service = Api::V1::PricingService.new(period:, hotel:, room:)
      service.run
      if service.valid?
        data = { rate: service.result }
        data[:disclaimer] = service.disclaimer if service.disclaimer.present?
        render_success(data)
      else
        error_msg = service.errors.join(', ')
        if service.errors.any? { |e| e.include?("unavailable") }
          render_error(error_msg, "SERVICE_UNAVAILABLE", :service_unavailable)
        elsif service.errors.any? { |e| e.include?("not found") }
          render_error(error_msg, "RATE_NOT_FOUND", :not_found)
        else
          render_error(error_msg, "GENERIC_ERROR", :bad_request)
        end
      end
    rescue => e
      Rails.logger.error("PricingController index unexpected error: #{e.class} - #{e.message}\n#{e.backtrace.first(10).join("\n")}")
      render_error("An unexpected internal error occurred. Please try again later.", "INTERNAL_SERVER_ERROR", :internal_server_error)
    end
  end

  private

  def render_success(data)
    render json: {
      resultInfo: {
        code: "S",
        message: "Success",
        codeId: "1"
      },
      data: data
    }
  end

  def render_error(message, code_id, status)
    render json: {
      resultInfo: {
        code: "F",
        message: message,
        codeId: code_id
      },
      data: nil
    }, status: status
  end

  def validate_params
    # Validate required parameters
    unless params[:period].present? && params[:hotel].present? && params[:room].present?
      Observability::Metrics.observe_validation_failure(:missing_params)
      return render_error("Missing required parameters: period, hotel, room", "INVALID_PARAMETERS", :bad_request)
    end

    # Validate parameter values
    unless VALID_PERIODS.include?(params[:period])
      Observability::Metrics.observe_validation_failure(:period)
      return render_error("Invalid period. Must be one of: #{VALID_PERIODS.join(', ')}", "INVALID_PARAMETERS", :bad_request)
    end

    unless VALID_HOTELS.include?(params[:hotel])
      Observability::Metrics.observe_validation_failure(:hotel)
      return render_error("Invalid hotel. Must be one of: #{VALID_HOTELS.join(', ')}", "INVALID_PARAMETERS", :bad_request)
    end

    unless VALID_ROOMS.include?(params[:room])
      Observability::Metrics.observe_validation_failure(:room)
      return render_error("Invalid room. Must be one of: #{VALID_ROOMS.join(', ')}", "INVALID_PARAMETERS", :bad_request)
    end
  end
end
