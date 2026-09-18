package com.secureattend

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication
import org.springframework.scheduling.annotation.EnableScheduling

@SpringBootApplication
@EnableScheduling
class SecureAttendApplication

fun main(args: Array<String>) {
    runApplication<SecureAttendApplication>(*args)
}
