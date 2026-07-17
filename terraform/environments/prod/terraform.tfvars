vpc_cidr                      = "10.0.1.0/16"
environment                   = "Prod"
retention_in_days             = 15
enable_deletion_protection    = true
sqs_message_retention_seconds = 86400
sqs_max_receive_count         = 2
skip_final_snapshot           = false
multi_az                      = true
instance_class                = "db.t4g.large"



