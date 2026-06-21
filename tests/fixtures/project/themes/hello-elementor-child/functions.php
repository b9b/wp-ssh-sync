<?php

add_action('wp_enqueue_scripts', function () {
    wp_enqueue_style('hello-elementor-child-test-fixture', get_stylesheet_uri());
});
