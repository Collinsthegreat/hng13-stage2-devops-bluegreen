For this project, I implemented a dynamic Blue/Green deployment strategy using environment-driven template rendering. The primary and backup application pools (Blue and Green) are controlled via environment variables, allowing Nginx to dynamically generate its configuration with the correct routing.  

During runtime, Nginx acts as the traffic router and handles failover automatically. When the active pool encounters issues (simulated via chaos testing), Nginx switches traffic to the backup pool. This ensures that users experience minimal downtime.  

Healthchecks for both Blue and Green containers are continuously monitored, and the system automatically retries or fails over based on container health. This setup allows for seamless deployments, safe rollbacks, and high availability without manual intervention.  

The approach prioritizes resilience, maintainability, and observability, making it easy to manage multiple releases while ensuring that the application remains responsive and reliable during updates or failures.
