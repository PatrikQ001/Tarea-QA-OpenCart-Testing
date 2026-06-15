# OpenCart 4.1.0.4 on PHP 8.2 + Apache, for Railway (or any Docker host)
FROM php:8.2-apache

# System libraries required by the PHP extensions OpenCart needs
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpng-dev \
        libjpeg62-turbo-dev \
        libfreetype6-dev \
        libzip-dev \
        libonig-dev \
        libicu-dev \
        libcurl4-openssl-dev \
        default-mysql-client \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" mysqli gd curl zip mbstring intl \
    && rm -rf /var/lib/apt/lists/*

# OpenCart relies on URL rewriting
RUN a2enmod rewrite

# Webroot = upload/ (OpenCart store root)
COPY upload/ /var/www/html/

# OpenCart ships .htaccess as .htaccess.txt
RUN if [ -f /var/www/html/.htaccess.txt ]; then \
        cp /var/www/html/.htaccess.txt /var/www/html/.htaccess; \
    fi

# Allow Apache to override; permissions on writable trees
RUN sed -ri 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
    && chown -R www-data:www-data /var/www/html \
    && chmod -R 775 /var/www/html/system/storage /var/www/html/image

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
