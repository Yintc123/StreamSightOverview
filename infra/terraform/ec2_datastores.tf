locals {
  # Render the compose file with real credentials, then embed it into user_data.
  compose_rendered = templatefile("${path.module}/templates/compose.yml.tftpl", {
    db_root_password = var.db_root_password
    db_name          = var.db_name
    db_user          = var.db_user
    db_password      = var.db_password
    redis_password   = var.redis_password
  })

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    compose_content = local.compose_rendered
  })
}

# Dedicated EBS volume for datastore persistence, kept in the instance's AZ.
resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.datastore.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  tags              = { Name = "${var.project}-data" }
}

resource "aws_instance" "datastore" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.ec2_instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.datastore.id]
  key_name               = var.key_pair_name == "" ? null : var.key_pair_name
  user_data              = local.user_data

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = { Name = "${var.project}-datastore" }

  # user_data embeds credentials; changing it forces a rebuild — do that deliberately.
  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.datastore.id
}
