variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "europe-west3"
}
variable "suffix" {
  type        = string
  description = "Globally unique bucket suffix, 3-12 lowercase letters or numbers"
  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.suffix))
    error_message = "Use 3-12 lowercase letters or numbers."
  }
}
variable "image" {
  type        = string
  description = "Prebuilt container image URI; build it before the 20-minute session"
}
