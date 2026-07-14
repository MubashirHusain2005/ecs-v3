##Acts as the main queue

resource "aws_sqs_queue" "main_queue" {
  name                      = "main-sqs-queue"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 345600
  receive_wait_time_seconds = 0
  sqs_managed_sse_enabled   = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter_queue.arn
    maxReceiveCount     = 4
  })
  tags = {
    Environment = "production"
  }
}


#Acts as the dead letter queue, so if the message fails to send after 5 attempts it goes here for debugging
resource "aws_sqs_queue" "dead_letter_queue" {
  name = "dead_letter_queue"

  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

}


resource "aws_sqs_queue_redrive_allow_policy" "deadletter_queue_redrive_allow_policy" {
  queue_url = aws_sqs_queue.dead_letter_queue.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main_queue.arn]
  })
}