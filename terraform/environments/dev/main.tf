##Modules

module "vpc" {
  source             = "../../modules/vpc"
  vpc_flow_logs_role = module.iam.vpc_flow_logs_role
}

module "ecs" {
  source                      = "../../modules/ecs"
  vpc_id                      = module.vpc.vpc_id
  ecs_task_execution_role         = module.iam.ecs_task_execution_role
  public_subnet_ids           = module.vpc.public_subnet_ids
  private_subnet_ids          = module.vpc.private_subnet_ids
  ecs_task_role              = module.iam.ecs_task_role
  dashboard_db_url_secret_arn = module.rds.dashboard_db_url_secret_arn
  main_queue_url              = module.sqs.main_queue_url
  redis_endpoint                  = module.elasticache.redis_endpoint
  alb_sg                      = module.alb.alb_sg
  dashboard_api_tg            = module.alb.dashboard_api_tg
  api_gateway_tg              = module.alb.api_gateway_tg
  vpce_sg = module.vpc.vpce_sg

}

module "elasticache" {
  source             = "../../modules/elasticache"
  private_subnet_ids = module.vpc.private_subnet_ids
  vpc_id             = module.vpc.vpc_id

}

module "iam" {
  source = "../../modules/iam"

}

module "alb" {
  source              = "../../modules/alb"
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  acm_certificate_arn = module.acm.acm_certificate_arn
  ecs_sg              = module.ecs.ecs_sg

}

module "acm" {
  source       = "../../modules/acm"
  alb_dns_name = module.alb.alb_dns_name
  alb_zone  = module.alb.alb_zone

}


module "rds" {
  source             = "../../modules/rds"
  private_subnet_ids = module.vpc.private_subnet_ids
  vpc_id             = module.vpc.vpc_id
  ecs_sg             = module.ecs.ecs_sg
}

module "sqs" {
  source = "../../modules/sqs"
}
