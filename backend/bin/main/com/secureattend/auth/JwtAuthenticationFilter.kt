package com.secureattend.auth

import com.secureattend.common.entity.UserRole
import com.secureattend.common.repository.UserRepository
import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken
import org.springframework.security.core.authority.SimpleGrantedAuthority
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter

@Component
class JwtAuthenticationFilter(
    private val jwtService: JwtService,
    private val userRepository: UserRepository
) : OncePerRequestFilter() {

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain
    ) {
        val authHeader = request.getHeader("Authorization")

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            filterChain.doFilter(request, response)
            return
        }

        val token = authHeader.substring(7)
        val claims = jwtService.validateToken(token)

        if (claims != null && !jwtService.isRefreshToken(claims) && SecurityContextHolder.getContext().authentication == null) {
            val userId = claims.subject
            val roleName = claims.get("role", String::class.java)

            if (userId != null && roleName != null) {
                val authorities = listOf(SimpleGrantedAuthority("ROLE_$roleName"))

                val authentication = UsernamePasswordAuthenticationToken(
                    userId,  // principal = user ID as string
                    null,    // credentials
                    authorities
                )
                authentication.details = WebAuthenticationDetailsSource().buildDetails(request)
                SecurityContextHolder.getContext().authentication = authentication
            }
        }

        filterChain.doFilter(request, response)
    }
}
