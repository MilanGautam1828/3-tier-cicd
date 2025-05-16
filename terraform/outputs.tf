output "backend_alb_dns" {
  value = aws_lb.backend_alb.dns_name
}
