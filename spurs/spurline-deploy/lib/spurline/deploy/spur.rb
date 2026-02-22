# frozen_string_literal: true

module Spurline
  module Deploy
    class Spur < Spurline::Spur
      spur_name :deploy

      tools do
        register :generate_deploy_plan, Spurline::Deploy::Tools::GenerateDeployPlan
        register :validate_deploy_prereqs, Spurline::Deploy::Tools::ValidateDeployPrereqs
        register :execute_deploy_step, Spurline::Deploy::Tools::ExecuteDeployStep
        register :rollback_deploy, Spurline::Deploy::Tools::RollbackDeploy
      end

      permissions do
        default_trust :external
        requires_confirmation true
      end
    end
  end
end
