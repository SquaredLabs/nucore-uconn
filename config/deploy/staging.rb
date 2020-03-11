# frozen_string_literal: true

<<<<<<< HEAD
server "test.cider.core.uconn.edu", user: "deploy", roles: %w(web app db)
set :deploy_to, "/home/deploy/workspace/deploy"
set :rails_env, "stage"
set :branch, ENV["CIRCLE_SHA1"] || ENV["REVISION"] || ENV["BRANCH_NAME"] || "master"
=======
set :branch, ENV["CIRCLE_SHA1"] || ENV["REVISION"] || ENV["BRANCH_NAME"] || "master"
set :rails_env, "stage"

server "tablexi-shared02.txihosting.com", user: "nucore", roles: %w(web app db)
set :deploy_to, "/home/nucore/nucore.stage.tablexi.com"
>>>>>>> upstream/master
